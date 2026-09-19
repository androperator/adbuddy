/* ADBuddy additions to scrcpy 4.1, Apache-2.0.
 * Included by recorder.c. Only enabled for our video-only H.264 recording mode.
 * Keep the upstream transport and packet queue; start a new MP4 at a keyframe
 * when the encoded dimensions change. No decoder, encoder, or server restart.
 */
#include <unistd.h>

struct adbuddy_segment {
    AVFormatContext *ctx;
    AVPacket *previous;
    int64_t origin;
    int width;
    int height;
    char *path;
    char *partial_path;
};

static bool
adbuddy_write_previous(struct adbuddy_segment *segment, int64_t next_pts) {
    AVPacket *packet = segment->previous;
    if (!packet) {
        return true;
    }
    int64_t timestamp = packet->pts;
    packet->duration = next_pts == AV_NOPTS_VALUE ? 100000
                                                : next_pts - timestamp;
    packet->pts -= segment->origin;
    packet->dts = packet->pts;
    packet->stream_index = 0;
    sc_recorder_rescale_packet(segment->ctx->streams[0], packet);
    bool ok = av_interleaved_write_frame(segment->ctx, packet) >= 0;
    av_packet_free(&segment->previous);
    return ok;
}

static bool
adbuddy_finish_segment(struct adbuddy_segment *segment, int64_t next_pts) {
    if (!segment->ctx) {
        return true;
    }
    bool ok = adbuddy_write_previous(segment, next_pts);
    if (av_write_trailer(segment->ctx) < 0) {
        ok = false;
    }
    if (avio_closep(&segment->ctx->pb) < 0) {
        ok = false;
    }
    avformat_free_context(segment->ctx);
    segment->ctx = NULL;
    // Only completed MP4s are exposed to the Swift service. link() refuses to
    // replace an existing file, even if the destination appears during capture.
    if (ok && link(segment->partial_path, segment->path) < 0) {
        ok = false;
    }
    unlink(segment->partial_path);
    if (ok) {
        LOGI("ADBuddy clip saved: %s (%dx%d)", segment->path,
             segment->width, segment->height);
    }
    free(segment->path);
    free(segment->partial_path);
    segment->path = NULL;
    segment->partial_path = NULL;
    return ok;
}

static bool
adbuddy_start_segment(struct adbuddy_segment *segment, const char *base_path,
                      unsigned index, const AVCodecParameters *parameters,
                      const AVPacket *config, int width, int height,
                      int64_t origin) {
    if (asprintf(&segment->path, "%s.%04u.mp4", base_path, index) < 0) {
        segment->path = NULL;
        return false;
    }
    if (asprintf(&segment->partial_path, "%s.inprogress", segment->path) < 0) {
        segment->partial_path = NULL;
        goto error;
    }
    if (access(segment->path, F_OK) == 0 || access(segment->partial_path, F_OK) == 0) {
        goto error;
    }
    if (avformat_alloc_output_context2(&segment->ctx, NULL, "mp4",
                                       segment->partial_path) < 0) {
        goto error;
    }
    AVStream *stream = avformat_new_stream(segment->ctx, NULL);
    if (!stream || avcodec_parameters_copy(stream->codecpar, parameters) < 0) {
        goto error;
    }
    av_freep(&stream->codecpar->extradata);
    stream->codecpar->extradata_size = 0;
    // FFmpeg requires padding after codec extradata.
    stream->codecpar->extradata = av_mallocz(config->size + AV_INPUT_BUFFER_PADDING_SIZE);
    if (!stream->codecpar->extradata) {
        goto error;
    }
    memcpy(stream->codecpar->extradata, config->data, config->size);
    stream->codecpar->extradata_size = config->size;
    stream->codecpar->width = width;
    stream->codecpar->height = height;
    stream->time_base = SCRCPY_TIME_BASE;
    if (avio_open(&segment->ctx->pb, segment->partial_path, AVIO_FLAG_WRITE) < 0
            || avformat_write_header(segment->ctx, NULL) < 0) {
        goto error;
    }
    segment->width = width;
    segment->height = height;
    segment->origin = origin;
    return true;

error:
    if (segment->ctx) {
        if (segment->ctx->pb) {
            avio_closep(&segment->ctx->pb);
            unlink(segment->partial_path);
        }
        avformat_free_context(segment->ctx);
        segment->ctx = NULL;
    }
    free(segment->path);
    free(segment->partial_path);
    segment->path = NULL;
    segment->partial_path = NULL;
    return false;
}

static bool
adbuddy_record_segments(struct sc_recorder *recorder) {
    if (!recorder->video || recorder->audio || recorder->orientation != SC_ORIENTATION_0) {
        LOGE("ADBuddy segmented recording requires video-only capture at orientation 0");
        return false;
    }
    // The upstream packet sink initializes codec parameters on this context.
    recorder->ctx = avformat_alloc_context();
    if (!recorder->ctx) {
        return false;
    }
    AVCodecParserContext *parser = av_parser_init(AV_CODEC_ID_H264);
    AVCodecContext *codec = avcodec_alloc_context3(NULL);
    AVPacket *config = NULL;
    struct adbuddy_segment segment = {0};
    unsigned count = 0;
    bool ok = parser && codec;
    if (!ok) {
        goto end;
    }
    parser->flags |= PARSER_FLAG_COMPLETE_FRAMES;
    codec->codec_id = AV_CODEC_ID_H264;

    for (;;) {
        sc_mutex_lock(&recorder->mutex);
        while (!recorder->stopped && sc_vecdeque_is_empty(&recorder->video_queue)) {
            sc_cond_wait(&recorder->cond, &recorder->mutex);
        }
        if (sc_vecdeque_is_empty(&recorder->video_queue)) {
            sc_mutex_unlock(&recorder->mutex);
            break;
        }
        AVPacket *packet = sc_vecdeque_pop(&recorder->video_queue);
        sc_mutex_unlock(&recorder->mutex);

        if (packet->pts == AV_NOPTS_VALUE) {
            av_packet_free(&config);
            config = packet;
            continue;
        }
        uint8_t *parsed_data;
        int parsed_size;
        int consumed = av_parser_parse2(parser, codec, &parsed_data, &parsed_size,
                                        packet->data, packet->size,
                                        packet->pts, packet->dts, 0);
        int width = parser->width;
        int height = parser->height;
        if (consumed < 0 || !config || width <= 0 || height <= 0) {
            LOGE("Could not read recording frame dimensions");
            av_packet_free(&packet);
            ok = false;
            break;
        }
        if (!segment.ctx || width != segment.width || height != segment.height) {
            if (!(packet->flags & AV_PKT_FLAG_KEY)) {
                LOGE("Recording dimensions changed without a keyframe");
                av_packet_free(&packet);
                ok = false;
                break;
            }
            ok = adbuddy_finish_segment(&segment, packet->pts);
            if (ok) {
                ok = adbuddy_start_segment(&segment, recorder->filename, ++count,
                    recorder->ctx->streams[0]->codecpar, config, width, height, packet->pts);
            }
            if (!ok) {
                av_packet_free(&packet);
                break;
            }
        }
        if (!adbuddy_write_previous(&segment, packet->pts)) {
            av_packet_free(&packet);
            ok = false;
            break;
        }
        segment.previous = packet;
    }

end:
    if (!adbuddy_finish_segment(&segment, AV_NOPTS_VALUE)) {
        ok = false;
    }
    av_packet_free(&config);
    if (parser) {
        av_parser_close(parser);
    }
    avcodec_free_context(&codec);
    // Wait for packet producers to observe stopped before freeing the context
    // they initialize. The caller will clear queues and notify the session.
    sc_mutex_lock(&recorder->mutex);
    recorder->stopped = true;
    avformat_free_context(recorder->ctx);
    recorder->ctx = NULL;
    sc_mutex_unlock(&recorder->mutex);
    return ok && count > 0;
}
