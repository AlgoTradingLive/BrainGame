import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

// ===================== AdMob IDs =====================
// App ID goes in android/app/src/main/AndroidManifest.xml (meta-data), NOT here.
const String kInterstitialAdUnitId = 'ca-app-pub-6724873553204610/7301847467';
const String kBannerAdUnitId = 'ca-app-pub-6724873553204610/5949272732';
const String kRewardedAdUnitId = 'ca-app-pub-6724873553204610/6943658774';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Android 16 (API 36) पासून edge-to-edge जबरदस्तीने लागू होतो —
  // हे explicitly सेट केल्याने layout/rendering वेळेत होतं आणि
  // black-screen delay कमी होतो.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.black,
    ),
  );

  MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Math Arena',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(scaffoldBackgroundColor: Colors.black),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  InAppWebViewController? _webViewController;

  // ---- Interstitial ----
  InterstitialAd? _interstitialAd;
  bool _interstitialReady = false;

  // ---- Banner (always visible, independent of the ads toggle) ----
  BannerAd? _bannerAd;
  bool _bannerReady = false;

  // ---- Rewarded (video watched -> coins in the HTML/JS side) ----
  RewardedAd? _rewardedAd;
  bool _rewardedReady = false;

  // Mirrors the HTML "Ads ON/OFF" toggle. Only gates the INTERSTITIAL —
  // the banner keeps showing no matter what this is set to.
  bool _adsEnabled = true;

  // Splash removal safety net
  bool _splashRemoved = false;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadInterstitialAd();
    _loadRewardedAd();

    // Safety net: जर WebView काही कारणाने onLoadStop पर्यंत पोहोचला नाही
    // तरी 1.5 सेकंदांनंतर splash आपोआप निघेल.
    Future.delayed(const Duration(milliseconds: 1500), _removeSplash);
  }

  void _removeSplash() {
    if (!_splashRemoved) {
      _splashRemoved = true;
      FlutterNativeSplash.remove();
    }
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    _bannerAd?.dispose();
    _rewardedAd?.dispose();
    super.dispose();
  }

  // ===================== Banner =====================
  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: kBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerReady = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerReady = false);
        },
      ),
    )..load();
  }

  // ===================== Interstitial =====================
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: kInterstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _interstitialReady = true;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _interstitialReady = false;
              _loadInterstitialAd(); // preload the next one
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _interstitialReady = false;
              _loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _interstitialReady = false;
          // Retry later instead of hammering AdMob with requests.
          Future.delayed(const Duration(seconds: 30), _loadInterstitialAd);
        },
      ),
    );
  }

  void _showInterstitialIfReady() {
    if (!_adsEnabled) return; // toggle OFF -> no interstitial
    if (_interstitialReady && _interstitialAd != null) {
      _interstitialAd!.show();
    }
  }

  // ===================== Rewarded =====================
  void _loadRewardedAd() {
    RewardedAd.load(
      adUnitId: kRewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _rewardedReady = true;
          _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedReady = false;
              _loadRewardedAd(); // preload the next one
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedReady = false;
              _loadRewardedAd();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _rewardedReady = false;
          // Retry later instead of hammering AdMob with requests.
          Future.delayed(const Duration(seconds: 30), _loadRewardedAd);
        },
      ),
    );
  }

  void _showRewardedIfReady() {
    if (!_adsEnabled) return; // toggle OFF -> no rewarded ad either
    if (_rewardedReady && _rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          // User watched the full video -> tell the HTML/JS side to
          // credit coins by calling onAdComplete() defined in BrainGame.html
          _webViewController?.evaluateJavascript(source: 'onAdComplete()');
        },
      );
    } else {
      // Ad not ready yet (still loading) -> try to fetch a fresh one
      // for next time, and let the HTML side show its own "loading" toast.
      _loadRewardedAd();
    }
  }

  // ===================== Bridge from HTML/JS =====================
  // Corresponds to BrainGame.html's sendToFlutter(val), which calls:
  //   window.flutter_inappwebview.callHandler('adBridge', val)
  void _handleWebMessage(String value) {
    switch (value) {
      case 'SHOW_INTERSTITIAL_AD':
        _showInterstitialIfReady();
        break;
      case 'SHOW_REWARDED_AD':
        _showRewardedIfReady();
        break;
      case 'ADS_ENABLED':
        _adsEnabled = true;
        break;
      case 'ADS_DISABLED':
        _adsEnabled = false;
        break;
      default:
        // LEVEL_COMPLETE, clap, boo, COINS_UPDATE|... — no native action needed.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InAppWebView(
                initialFile: 'assets/BrainGame.html',
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  supportZoom: false,
                  transparentBackground: true,
                ),
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  controller.addJavaScriptHandler(
                    handlerName: 'adBridge',
                    callback: (args) {
                      if (args.isNotEmpty) {
                        _handleWebMessage(args.first.toString());
                      }
                      return null;
                    },
                  );
                },
                onLoadStop: (controller, url) async {
                  // BrainGame.html पूर्ण लोड झाल्यावर native splash हटवा.
                  _removeSplash();
                },
              ),
            ),
            // Banner ad strip — always visible, unaffected by the ads toggle.
            if (_bannerReady && _bannerAd != null)
              SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }
}
