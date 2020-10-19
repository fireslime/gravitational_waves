import 'dart:async';
import 'dart:io';

import 'package:firebase_admob/firebase_admob.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:oktoast/oktoast.dart';

import 'analytics.dart';
import 'util.dart';

class Ads {
  static bool _loaded;

  static bool _adsEnabled() {
    return ENABLE_ADS && !kIsWeb;
  }

  static bool adLoaded() {
    return _adsEnabled() && _loaded;
  }

  static String get appId => Platform.isIOS
      ? 'ca-app-pub-1572179540677968~8438800634'
      : 'ca-app-pub-1572179540677968~2049628478';

  static String get adUnitId => Platform.isIOS
      ? 'ca-app-pub-1572179540677968/3409835233'
      : 'ca-app-pub-1572179540677968/7034539450';

  static Future<void> init() async {
    if (_adsEnabled()) {
      _loaded = await FirebaseAdMob.instance.initialize(appId: appId);
      _loadAd(); // pre-loads an ad for the first time
    }
  }

  static _loadAd() async {
    await RewardedVideoAd.instance.load(
      adUnitId: adUnitId,
      targetingInfo: MobileAdTargetingInfo(
        keywords: [
          'game',
          'gravity',
          'runner',
          'platformer',
          'action',
          'fast',
        ],
        // temporarily add your test devices' id here to debug
        testDevices: [],
      ),
    );
  }

  static Future<bool> showAd() async {
    if (!_adsEnabled()) {
      return Future.value(false);
    }

    if (!_loaded) {
      showToast('There was an error while loading ads for the app.');
      return Future.value(false);
    }

    Analytics.log(EventName.REWARD);
    final promise = Completer<bool>();
    bool wasRewarded = false;

    RewardedVideoAd.instance.listener = (
      RewardedVideoAdEvent event, {
      String rewardType,
      int rewardAmount,
    }) {
      if (event == RewardedVideoAdEvent.rewarded) {
        wasRewarded = true;
      } else if (event == RewardedVideoAdEvent.closed) {
        _loadAd(); // loads a new ad for next time
        promise.complete(wasRewarded);
      }
    };

    try {
      final result = await RewardedVideoAd.instance.show();
      if (!result) {
        showToast('There was an error while showing the ad.');
        promise.complete(false);
      }
    } on PlatformException catch (ex) {
      if (ex.code == 'ad_not_loaded') {
        showToast(
          'The ad was still loading, please wait a few seconds and try again.',
        );
      } else {
        print('Unexpected error while loading ad: $ex');
        showToast('Unexpected error while loading the ad.');
      }
      promise.complete(false);
    } catch (ex) {
      print('Unexpected error while loading ad: $ex');
      showToast('Unexpected error while loading the ad.');
      promise.complete(false);
    }

    return promise.future;
  }
}
