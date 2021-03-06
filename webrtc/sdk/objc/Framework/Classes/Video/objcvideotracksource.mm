/*
 *  Copyright (c) 2017 The WebRTC project authors. All Rights Reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#include "webrtc/sdk/objc/Framework/Classes/Video/objcvideotracksource.h"

#import "RTCVideoFrame+Private.h"

#include "webrtc/api/video/i420_buffer.h"
#include "webrtc/sdk/objc/Framework/Classes/Video/corevideo_frame_buffer.h"

namespace webrtc {

ObjcVideoTrackSource::ObjcVideoTrackSource() {}

void ObjcVideoTrackSource::OnOutputFormatRequest(int width, int height, int fps) {
  cricket::VideoFormat format(width, height, cricket::VideoFormat::FpsToInterval(fps), 0);
  video_adapter()->OnOutputFormatRequest(format);
}

void ObjcVideoTrackSource::OnCapturedFrame(RTCVideoFrame* frame) {
  const int64_t timestamp_us = frame.timeStampNs / rtc::kNumNanosecsPerMicrosec;
  const int64_t translated_timestamp_us =
      timestamp_aligner_.TranslateTimestamp(timestamp_us, rtc::TimeMicros());

  int adapted_width;
  int adapted_height;
  int crop_width;
  int crop_height;
  int crop_x;
  int crop_y;
  if (!AdaptFrame(frame.width, frame.height, timestamp_us, &adapted_width, &adapted_height,
                  &crop_width, &crop_height, &crop_x, &crop_y)) {
    return;
  }

  rtc::scoped_refptr<VideoFrameBuffer> buffer;
  if (adapted_width == frame.width && adapted_height == frame.height) {
    // No adaption - optimized path.
    buffer = frame.videoBuffer;
  } else if (frame.nativeHandle) {
    // Adapted CVPixelBuffer frame.
    buffer = new rtc::RefCountedObject<CoreVideoFrameBuffer>(
        static_cast<CVPixelBufferRef>(frame.nativeHandle), adapted_width, adapted_height,
        crop_width, crop_height, crop_x, crop_y);
  } else {
    // Adapted I420 frame.
    // TODO(magjed): Optimize this I420 path.
    rtc::scoped_refptr<I420Buffer> i420_buffer = I420Buffer::Create(adapted_width, adapted_height);
    i420_buffer->CropAndScaleFrom(
        *frame.videoBuffer->ToI420(), crop_x, crop_y, crop_width, crop_height);
    buffer = i420_buffer;
  }

  // Applying rotation is only supported for legacy reasons and performance is
  // not critical here.
  webrtc::VideoRotation rotation = static_cast<webrtc::VideoRotation>(frame.rotation);
  if (apply_rotation() && rotation != kVideoRotation_0) {
    buffer = I420Buffer::Rotate(*buffer->ToI420(), rotation);
    rotation = kVideoRotation_0;
  }

  OnFrame(webrtc::VideoFrame(buffer, rotation, translated_timestamp_us));
}

}  // namespace webrtc
