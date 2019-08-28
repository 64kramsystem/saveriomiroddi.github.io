---
layout: post
title: Converting/processing a video using FFmpeg, for viewing on an old digital media player
tags: [linux,ffmpeg,media_processing]
last_modified_at: 2019-08-28 16:47:00
---

During my last vacation, I wanted to watch some very old cartoons, during the daily break, on the digital media player that the apartment provided.

The player was very old, and couldn't handle the video file (a modern MP4). Therefore, this was a good occasion to exercise the [FFmpeg](https://en.wikipedia.org/wiki/FFmpeg) conversion and processing capabilities.

This post will give a glimpse of the tools that FFmpeg provides, showing how easy it is to perform the video/audio conversion, with extra processing.

I will also explain general concepts of media handling, like containers and encoding formats.

Contents:

- [What is FFmpeg (and Libav)](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#what-is-ffmpeg-and-libav)
- [A brief introduction to video file related concepts and formats](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#a-brief-introduction-to-video-file-related-concepts-and-formats)
- [First attempt: a basic audio/video conversion](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#first-attempt-a-basic-audiovideo-conversion)
- [Interlude: encoding bitrate modes](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#interlude-encoding-bitrate-modes)
- [Scaling (down) the video](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#scaling-down-the-video)
- [Backpedaling to CBR](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#backpedaling-to-cbr)
- [Mixing (down) the audio channels](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#mixing-down-the-audio-channels)
- [Splitting the file](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#splitting-the-file)
- [Conclusion](/Converting-processing-a-video-using-ffmpeg-for-viewing-on-an-digital-media-player#conclusion)

## What is FFmpeg (and Libav)

FFmpeg is a "free and open-source project consisting of a vast software suite of libraries and programs for handling video, audio, and other media files and streams".

From a practical perspective, the user uses a single executable, `ffmpeg`, which, through a huge (but logical and consistent) amount of switches, can perform operations on media files.

FFmpeg is (or better, has been) associated with [Libav](https://en.wikipedia.org/wiki/Libav), a fork that has seen some success in the past, but it seems dead(-ish) in the present.

For the sake of this article, both are equivalent (except that the Libav binary is named `avconv`). Modern Ubuntu versions ship with FFmpeg, although in the past, they shipped for a while with Libav.

A good starting point for understanding the fork history is an [LWN article](https://lwn.net/Articles/650816), which strives to stay neutral.

## A brief introduction to video file related concepts and formats

After reading the related section of the player manual, I gathered that the supported video format is [AVI](https://en.wikipedia.org/wiki/Audio_Video_Interleave).

AVI is a very old container format, and limited, by today's standards. It has been for a long time used for distributions of movies whose video was encoded in the famous DivX format, which marked the beginning of the online movies piracy.

As a matter of fact, to be specific, the player supports DivX video and MP3 audio streams stored in an AVI container.

Note how I've separated the concept of "container" (AVI) and "streams" (video and audio). This must be kept in mind; for example, "MP4 audio files" are a common source of confusion: technically, to be exact, [MP4](https://en.wikipedia.org/wiki/MPEG-4_Part_14) is the container, while the audio stream encoding format is [AAC](https://en.wikipedia.org/wiki/Advanced_Audio_Coding).

Containers have other characteristics. Modern ones, like [Matroska](https://en.wikipedia.org/wiki/Matroska) (`.mkv`), support subtitles and chapter markers (among other functionalities).

AVI limitations will cause me a problem, as seen in the last section, but for this player, it's the only choice.

## First attempt: a basic audio/video conversion

We start with a straight conversion. As efficiency nerd, I'll use variable bitrate encoding for both audio and video. This is the command:

```sh
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -qscale:v 4 -c:a libmp3lame -qscale:a 5 output.avi
```

Let's break it down:

- '`-i input.mp4`': input file;
- '`output.avi`': output file
  - FFmpeg will choose the container automatically based on the extension, which in this case will be AVI
- '`-c:v mpeg4`': [`c`]odec for the [`v`]ideo stream
  - the default for `mpeg` is Xvid, which in essence, is the open source DivX competitor
- '`-vtag xvid`': video code identifier
  - technically called ["FourCC"](https://en.wikipedia.org/wiki/FourCC)
  - we need to explicitly set this for maximum compatibility
- '`-qscale:v 4`': video quality
  - we use variable bitrate, with a quality factor of 4
    - this yielded an 1.6 GiB video stream, which is overkill for a 1280x720 source
- '`-c:a libmp3lame`': [`c`]odec for the [`a`]udio stream
  - [LAME](https://en.wikipedia.org/wiki/LAME) is the reference (open source) MP3 encoder
- '`-qscale:a 5`': audio quality
  - like the video encoding, we use variable bitrate, with a quality factor of 5
    - this yields in general, a rough bitrate of 130 kbps, at whom the vast majority of people can't distinguish an encoded file from the source **on a blind test, with a good encoder**

Although this is not a "tiny" amount of parameters, they're all very explicit and logical.

Result: the file won't play! The player says that there is a limit in the frame size of 800x600; since the input is 1280x720, we'll need to resize.

## Interlude: encoding bitrate modes

When it comes to encoding a stream (either video or audio), we need to choose the strategy for allocating the amount of data.

In order to achieve the maximum efficiency (as in maximum quality for the given average bitrate), we want a higher bitrate for the most complex segments, and a lower bitrate for the simpler ones.

[VBR](https://en.wikipedia.org/wiki/Variable_bitrate) ([`V`]ariable [`B`]it[`r`]ate) does this. All the most common media codecs support it.

The downside of this strategy is that it's not known, ahead of time, which will be the output size.

Opposed to this strategy, there's [CBR](https://en.wikipedia.org/wiki/Constant_bitrate) ([`C`]onstant [`B`]it[`r`]ate). This uses the same bitrate for all the segments. Obviously, this is a suboptimal strategy: the most complex segments will likely suffer, since they need more data to reach the desired quality, while the simpler ones will waste data.

In reality, even CBR is not exactly constant (as there is a ["bit reservoir"](https://wiki.hydrogenaud.io/index.php?title=Bit_reservoir)), but this is very limited.

The upside of CBR is that it's known ahead of time which is the output size.

A middle ground is the [ABR](https://en.wikipedia.org/wiki/Average_bitrate) ([`A`]verage [`B`]it[`r`]ate). The idea is that the encoder varies the bitrate during the encoding, while keeping, in the end, the desired average.

ABR is supported as much as VBR. There are two approaches to it:

- single pass: the encoder performs a single encoding pass, adjusting the bitrate where needed, but within the limits required to achieve the desired average bitrate *in the end*
- 2-pass: the encoder first performs an analysis of the complexity of the sequences, then, it performs the encoding

The 2-pass strategy is clearly superior - it brings together the best of VBR and CBR (ignoring the time required, which is higher due to the first pass).

The downside is that not all encoders support 2-pass encoding.

A final, counterintuitive, note, is that 1-pass ABR may not be necessarily worse than VBR. This is because if the VBR quantizer (encoder, in essence) makes a mistake in the estimation (too little or too much data allocated), we'll end up with suboptimal quality or waste of data; ABR, being more constrained, is less subject to mistaken fluctuations.  
Keep in mind, however, that nowadays, VBR is the standard, so the bulk of the optimization is geared towards this mode.

## Scaling (down) the video

In our second attempt we'll scale down the video, so that it will fit the encoder. This is the new command:

```sh
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -qscale:v 4 -vf scale=800:600 -c:a libmp3lame -qscale:a 5 output.avi
```

Very easy addition:

- '`-vf scale=800:600`': [`v`]ideo `filter`
  - we simply scale down to 800x600

Now the video plays! But there's something we can tweak.

Something I intentionally omitted is that the original video has a 16:9 aspect ratio, but the frame is actually a 4:3, so it shows distorted!

FFmpeg, appropriately, keeps the aspect ratio setting of 16:9, even if we encode to 800x600 (which is 4:3). What do we do? We enforce the aspect ratio:

```sh
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -qscale:v 4 -vf scale=800:600 -aspect 4:3 -c:a libmp3lame -qscale:a 5 output.avi
```

The option is very self-explanatory:

- '`-aspect 4:3`'

Now the aspect look good!

## Backpedaling to CBR

Does the video now work? Not properly! It's very choppy. Very likely, the player being very old, doesn't properly support VBR.

So we change from VBR to CBR. We're going to lose efficiency, but for this specific video, it's acceptable:

```sh
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -b:v 1000k -vf scale=800:600 -aspect 4:3 -c:a libmp3lame -b:a 96k output.avi
```

The changes is quite simple; we replace  with:

- '`-qscale:v 4`' -> '`-b:v 1000k`': [`b`]itrate of the [`v`]ideo
- '`-qscale:a 5`' -> '`-b:a 96k`': [`b`]itrate of the [`a`]udio

The inefficiency is painful, but we're constrained by the player.

The video now plays correctly! Can we do better? A few things, but notably, and for fun, something with the audio channels.

## Mixing (down) the audio channels

Let's assume that the audio is true stereo (that is, that the channels contains slightly different data). For watching a cartoon on an old and bad setup, this is overkill! 

We could downmix to mono, however some players, when reproducing a mono audio stream, output only on one speaker.

We don't take the risk of having to debug this, so we do something interesting: we mix both channels, and we output the same stream into two channels.

The advantage is that the encoder will find the same data for both channels, and won't require extra data for encoding the differences. The process of encoding multiple channels as one, plus the difference(s) is called ["Joint Stereo"](https://en.wikipedia.org/wiki/Joint_(audio_engineering)).

New command:

```sh
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -b:v 1000k -vf scale=800:600 -aspect 4:3 -c:a libmp3lame -b:a 96k 'pan=stereo|c0<c0+c1|c1<c0+c1' output.avi
```

The addition is relatively simple, but especially, very logical:

- '`-af pan=stereo|c0<c0+c1|c1<c0+c1`': [`a`]udio [`f`]ilter
  - downmix to `stereo`
  - channel 0 (`c0`) will be the sum of the original channels 0 + 1  (`c0+c1`)
  - channel 1 (`c1`) will also be the sum of the original channels 0 + 1  (`c0+c1`)

In addition to playing correctly, the encoding satisfy the need for (useless and negligible) efficiency.

We still have a problem: watching in multiple sessions.

## Splitting the file

The entire video is around 90 minutes; a screen time of 10/15 minutes per day is enough.

The problem is that the player doesn't have any mean to fast forward by large amounts of time. So, on each day, I should fast forward by (day_N₁ - 1) * 10  minutes, which is time consuming.

Modern containers support chapter markers. This is really cool: we can, say, set one every 10 minutes, and jump to each directly.

Big problem: AVI doesn't support, in the (standard) specification, chapters.

Again, we don't want to be testers for the player capacity, so we can apply the simplest solution: splitting.

In theory, I could have taken the input file, open it into an editor, and split precisely between episodes. This is overkill, plus it's a manual process.

On the other end of the spectrum, we could split at exactly fixed intervals. This works, but we can do better.

So we can regress a bit on the spectrum, and make FFmpeg split on a change of scene. This is still a bit annoying when playing, but it's the best we can do in an automated fashion (excluding machine learning, which is interesting, but outside the scope of this article).

Final command:

```sh
ffmpeg -i input.mp4 -c:v mpeg4 -vtag xvid -b:v 1000k -vf scale=800:600 -aspect 4:3 -c:a libmp3lame -b:a 96k -af 'pan=stereo|c0<c0+c1|c1<c0+c1' -segment_time 00:10:00 -reset_timestamps 1 -f segment output%02d.avi
```

The changes are:

- '`-segment_time 00:10:00`': split in segments, using  of 10 minutes time interval, 
- '`-reset_timestamps 1`': needed for compatibility reasons
- '`-f segment output%02d.avi`': format the output filename (using the `printf` format); in this case a 2-characters long decimal (`outputNN.avi`)

From a technical perspective, the "change of scene" is actually a new [keyframe](https://en.wikipedia.org/wiki/Key_frame) - the reference frame on a video sequence, which can be somewhat associated to the start of a new scene.

The result is actually underwhelming, but it's an interesting concept to explore nonetheless. Also note that I've ignored the mapping concept, which in simple cases like this is not needed.

For the segmentation concept, the reference is the [FFmpeg documentation](https://www.ffmpeg.org/ffmpeg-formats.html#segment_002c-stream_005fsegment_002c-ssegment).

## Conclusion

While the FFmpeg commandline tool violates the Unix philosophy of [Do One Thing and Do It Well](https://en.wikipedia.org/wiki/Unix_philosophy#Do_One_Thing_and_Do_It_Well), it still provides a cleanly designed user interface, whose strongest point is, in my opinion, the progression: basic concepts are applicable in a simple way (to the point of being automated, like the default output format based on the filename extension), while more advanced ones can be incrementally added.

Following this principle, we've easily integrated advanced concepts like audio mixing and segmentation in a basic media file conversion.

FFmpeg is pretty much universally available; consider it for your basic media operations!
