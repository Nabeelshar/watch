import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/config.dart';

class AdConsent {
  static bool _initialized = false;
  static Future<bool> prepare() async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return false;
    }
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (!done.isCompleted) done.complete();
        });
      },
      (error) {
        if (!done.isCompleted) done.complete();
      },
    );
    await done.future;
    final allowed = await ConsentInformation.instance.canRequestAds();
    if (allowed && !_initialized) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }
    return allowed;
  }

  static Future<void> privacy() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      done.complete();
    });
    await done.future;
  }
}

class PartyAdBanner extends StatefulWidget {
  const PartyAdBanner({super.key});
  @override
  State<PartyAdBanner> createState() => _PartyAdBannerState();
}

class _PartyAdBannerState extends State<PartyAdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _width;
  int _generation = 0;
  Future<void> _load(int width) async {
    final generation = ++_generation;
    _ad?.dispose();
    _ad = null;
    _loaded = false;
    if (mounted) setState(() {});
    if (width < 250) return;
    try {
      if (!await AdConsent.prepare() || !mounted || generation != _generation) {
        return;
      }
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      if (size == null || !mounted || generation != _generation) return;
      final ad = BannerAd(
        adUnitId: defaultTargetPlatform == TargetPlatform.iOS
            ? AppConfig.iosBanner
            : AppConfig.androidBanner,
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted && generation == _generation) {
              setState(() => _loaded = true);
            } else {
              ad.dispose();
            }
          },
          onAdFailedToLoad: (ad, error) {
            ad.dispose();
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      /* An unavailable ad never blocks the room. */
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.floor().clamp(0, 728);
      if (_width != width) {
        _width = width;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_load(width));
        });
      }
      return !_loaded || _ad == null
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(
                    'Advertisement',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: _ad!.size.width.toDouble(),
                    height: _ad!.size.height.toDouble(),
                    child: AdWidget(ad: _ad!),
                  ),
                ],
              ),
            );
    },
  );
  @override
  void dispose() {
    _generation++;
    _ad?.dispose();
    super.dispose();
  }
}
