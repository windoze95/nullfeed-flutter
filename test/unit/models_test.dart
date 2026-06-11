import 'package:flutter_test/flutter_test.dart';
import 'package:nullfeed/models/channel.dart';
import 'package:nullfeed/models/json_converters.dart';
import 'package:nullfeed/models/user.dart';
import 'package:nullfeed/models/video.dart';
import 'package:nullfeed/models/youtube_import.dart';

void main() {
  group('datetime converters', () {
    test('parses naive (offset-less) values as UTC', () {
      final parsed = dateTimeFromJson('2026-06-11T10:30:00');
      expect(parsed, DateTime.utc(2026, 6, 11, 10, 30));
      expect(parsed.isUtc, isTrue);
    });

    test('parses naive values with fractional seconds as UTC', () {
      final parsed = dateTimeFromJson('2026-06-11T10:30:00.123456');
      expect(parsed.isUtc, isTrue);
      expect(parsed.millisecond, 123);
    });

    test('leaves values with an explicit Z offset untouched', () {
      expect(
        dateTimeFromJson('2026-06-11T10:30:00Z'),
        DateTime.utc(2026, 6, 11, 10, 30),
      );
    });

    test('respects an explicit numeric offset', () {
      expect(
        dateTimeFromJson('2026-06-11T12:30:00+02:00'),
        DateTime.utc(2026, 6, 11, 10, 30),
      );
      expect(
        dateTimeFromJson('2026-06-11T08:30:00-02:00'),
        DateTime.utc(2026, 6, 11, 10, 30),
      );
    });

    test('nullable variant passes null through', () {
      expect(nullableDateTimeFromJson(null), isNull);
      expect(
        nullableDateTimeFromJson('2026-06-11T10:30:00'),
        DateTime.utc(2026, 6, 11, 10, 30),
      );
    });
  });

  group('User', () {
    test('parses has_pin and a naive created_at', () {
      final user = User.fromJson(const {
        'id': 'u1',
        'display_name': 'Julian',
        'avatar_url': '/data/thumbnails/avatars/u1.jpg',
        'is_admin': true,
        'has_pin': true,
        'created_at': '2026-06-11T10:30:00',
      });

      expect(user.id, 'u1');
      expect(user.displayName, 'Julian');
      expect(user.avatarUrl, '/data/thumbnails/avatars/u1.jpg');
      expect(user.isAdmin, isTrue);
      expect(user.hasPin, isTrue);
      expect(user.createdAt, DateTime.utc(2026, 6, 11, 10, 30));
      expect(user.createdAt.isUtc, isTrue);
    });

    test('has_pin defaults to false when absent', () {
      final user = User.fromJson(const {
        'id': 'u1',
        'display_name': 'Julian',
        'created_at': '2026-06-11T10:30:00Z',
      });

      expect(user.hasPin, isFalse);
      expect(user.isAdmin, isFalse);
      expect(user.avatarUrl, isNull);
    });

    test('survives a JSON round-trip', () {
      final user = User.fromJson(const {
        'id': 'u1',
        'display_name': 'Julian',
        'has_pin': true,
        'created_at': '2026-06-11T10:30:00',
      });

      expect(User.fromJson(user.toJson()), user);
    });
  });

  group('YoutubeProfile', () {
    test('parses the full resolve payload', () {
      final profile = YoutubeProfile.fromJson(const {
        'handle': '@mkbhd',
        'channel_id': 'UCBJycsmduvYEL83R_U4JriQ',
        'name': 'Marques Brownlee',
        'description': 'Quality tech videos',
        'avatar_url': 'https://yt3.googleusercontent.com/avatar.jpg',
        'banner_url': null,
        'follower_count': 21000000,
      });

      expect(profile.handle, '@mkbhd');
      expect(profile.channelId, 'UCBJycsmduvYEL83R_U4JriQ');
      expect(profile.name, 'Marques Brownlee');
      expect(profile.avatarUrl, 'https://yt3.googleusercontent.com/avatar.jpg');
      expect(profile.bannerUrl, isNull);
      expect(profile.followerCount, 21000000);
    });

    test('survives a JSON round-trip with optional fields absent', () {
      const profile = YoutubeProfile(
        handle: '@small',
        channelId: 'UCsmall',
        name: 'Small Channel',
      );

      expect(YoutubeProfile.fromJson(profile.toJson()), profile);
    });
  });

  group('ChannelSuggestion', () {
    test('parses the suggestions payload and defaults score to 0', () {
      final suggestion = ChannelSuggestion.fromJson(const {
        'youtube_channel_id': 'UCabc',
        'name': 'Some Channel',
        'handle': '@some',
        'avatar_url': null,
        'source': 'playlists',
      });

      expect(suggestion.youtubeChannelId, 'UCabc');
      expect(suggestion.name, 'Some Channel');
      expect(suggestion.handle, '@some');
      expect(suggestion.source, 'playlists');
      expect(suggestion.score, 0);
    });

    test('survives a JSON round-trip', () {
      const suggestion = ChannelSuggestion(
        youtubeChannelId: 'UCabc',
        name: 'Some Channel',
        source: 'featured',
        score: 100,
      );

      expect(ChannelSuggestion.fromJson(suggestion.toJson()), suggestion);
    });
  });

  group('BulkSubscribeResult', () {
    test('parses each result status shape', () {
      final ok = BulkSubscribeResult.fromJson(const {
        'youtube_channel_id': 'UCabc',
        'status': 'subscribed',
        'channel_id': 'c1',
      });
      final failed = BulkSubscribeResult.fromJson(const {
        'youtube_channel_id': 'UCxyz',
        'status': 'error',
        'detail': 'Could not resolve channel',
      });

      expect(ok.status, 'subscribed');
      expect(ok.channelId, 'c1');
      expect(ok.detail, isNull);
      expect(failed.status, 'error');
      expect(failed.detail, 'Could not resolve channel');
      expect(BulkSubscribeResult.fromJson(ok.toJson()), ok);
    });
  });

  group('Video', () {
    test('parses a naive uploaded_at as UTC and maps the status enum', () {
      final video = Video.fromJson(const {
        'id': 'v1',
        'youtube_video_id': 'yt1',
        'channel_id': 'c1',
        'title': 'A Video',
        'duration_seconds': 90,
        'uploaded_at': '2026-06-10T08:00:00',
        'status': 'COMPLETE',
      });

      expect(video.uploadedAt, DateTime.utc(2026, 6, 10, 8));
      expect(video.uploadedAt!.isUtc, isTrue);
      expect(video.status, VideoStatus.complete);
      expect(Video.fromJson(video.toJson()), video);
    });

    test('tolerates a null uploaded_at', () {
      final video = Video.fromJson(const {
        'id': 'v1',
        'youtube_video_id': 'yt1',
        'channel_id': 'c1',
        'title': 'A Video',
        'uploaded_at': null,
      });

      expect(video.uploadedAt, isNull);
      expect(video.status, VideoStatus.cataloged);
    });
  });

  group('Channel', () {
    test('parses a naive last_checked_at as UTC', () {
      final channel = Channel.fromJson(const {
        'id': 'c1',
        'youtube_channel_id': 'UCabc',
        'name': 'Some Channel',
        'slug': 'some-channel',
        'last_checked_at': '2026-06-11T09:15:00',
      });

      expect(channel.lastCheckedAt, DateTime.utc(2026, 6, 11, 9, 15));
      expect(channel.lastCheckedAt!.isUtc, isTrue);
      expect(Channel.fromJson(channel.toJson()), channel);
    });
  });
}
