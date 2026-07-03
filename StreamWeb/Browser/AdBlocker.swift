import Foundation
import WebKit

/// Lightweight, local ad filtering for the embedded browser.
/// It does not inspect cookies, form values, passwords, or page messages.
enum AdBlocker {
    private static let ruleListIdentifier = "StreamWeb.AdBlockRules.v2"

    private static let blockedHosts: Set<String> = [
        "33across.com",
        "adform.net",
        "adkernel.com",
        "admaven.com",
        "adnxs.com",
        "adsafeprotected.com",
        "adsterra.com",
        "adsrvr.org",
        "amazon-adsystem.com",
        "betweendigital.com",
        "bidgear.com",
        "bidvertiser.com",
        "casalemedia.com",
        "clickadu.com",
        "criteo.com",
        "criteo.net",
        "doubleclick.net",
        "exoclick.com",
        "googleadservices.com",
        "googlesyndication.com",
        "hilltopads.net",
        "juicyads.com",
        "lijit.com",
        "media.net",
        "mgid.com",
        "onclicka.com",
        "openx.net",
        "outbrain.com",
        "popads.net",
        "popcash.net",
        "propellerads.com",
        "propellerclick.com",
        "pubmatic.com",
        "revcontent.com",
        "rubiconproject.com",
        "serving-sys.com",
        "sharethrough.com",
        "smartadserver.com",
        "taboola.com",
        "teads.tv",
        "trafficjunky.net",
        "yieldmo.com"
    ]

    static func addCosmeticFilters(
        to userContentController: WKUserContentController,
        enabled: Bool
    ) {
        guard enabled else { return }

        let script = WKUserScript(
            source: cosmeticFilterScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(script)
    }

    static func installNetworkRules(
        into userContentController: WKUserContentController,
        enabled: Bool,
        completion: @escaping () -> Void
    ) {
        guard enabled else {
            completion()
            return
        }

        guard let store = WKContentRuleListStore.default() else {
            completion()
            return
        }

        store.lookUpContentRuleList(forIdentifier: ruleListIdentifier) { existingList, _ in
            if let existingList {
                DispatchQueue.main.async {
                    userContentController.add(existingList)
                    completion()
                }
                return
            }

            guard
                let rulesURL = Bundle.main.url(forResource: "AdBlockRules", withExtension: "json"),
                let encodedRules = try? String(contentsOf: rulesURL, encoding: .utf8)
            else {
                DispatchQueue.main.async { completion() }
                return
            }

            store.compileContentRuleList(
                forIdentifier: ruleListIdentifier,
                encodedContentRuleList: encodedRules
            ) { compiledList, _ in
                DispatchQueue.main.async {
                    if let compiledList {
                        userContentController.add(compiledList)
                    }
                    completion()
                }
            }
        }
    }

    static func shouldBlockNavigation(to url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        return blockedHosts.contains { blockedHost in
            host == blockedHost || host.hasSuffix(".\(blockedHost)")
        }
    }

    private static let cosmeticFilterScript = #"""
    (() => {
      const styleID = 'streamweb-adblock-style';
      const selectors = [
        '.adsbygoogle',
        '.ad-container',
        '.ad-wrapper',
        '.ad-banner',
        '.advertisement',
        '.advertising',
        '.sponsored-content',
        '[data-ad]',
        '[data-ad-slot]',
        '[data-ad-unit]',
        '[aria-label="advertisement"]',
        '[aria-label="Advertisement"]',
        'iframe[src*="doubleclick.net"]',
        'iframe[src*="googlesyndication.com"]',
        'iframe[src*="googleadservices.com"]',
        'iframe[src*="adsterra"]',
        'iframe[src*="propellerads"]',
        'iframe[src*="popads"]',
        'iframe[src*="popcash"]',
        'iframe[src*="onclicka"]',
        'iframe[src*="exoclick"]'
      ];

      const selectorText = selectors.join(',');

      if (!document.getElementById(styleID)) {
        const style = document.createElement('style');
        style.id = styleID;
        style.textContent = `${selectorText}{display:none!important;visibility:hidden!important;opacity:0!important;pointer-events:none!important;}`;
        (document.head || document.documentElement).appendChild(style);
      }

      const clean = (root) => {
        if (!root || !root.querySelectorAll) return;
        root.querySelectorAll(selectorText).forEach((element) => {
          element.style.setProperty('display', 'none', 'important');
          element.style.setProperty('visibility', 'hidden', 'important');
          element.style.setProperty('pointer-events', 'none', 'important');
        });
      };

      clean(document);

      const observer = new MutationObserver((records) => {
        for (const record of records) {
          for (const node of record.addedNodes) {
            if (node.nodeType === Node.ELEMENT_NODE) clean(node);
          }
        }
      });

      observer.observe(document.documentElement, { childList: true, subtree: true });
    })();
    """#
}
