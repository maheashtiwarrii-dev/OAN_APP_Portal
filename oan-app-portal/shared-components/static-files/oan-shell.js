/*
 * OAN Portal shell (Build Pack §3.2, wave W1). Loaded on every page via the application's
 * JavaScript file URLs, because the global page cannot carry page-level JavaScript.
 *   1. Notification badge: refreshed every 60s while the tab is visible (OAN_UNREAD_COUNT).
 *   2. Profile card: moved from the drawers slot to the top of the left rail.
 *   3. Global search box: opens search results (page 19) with the typed terms.
 *   4. Carousel (Home leadership letters): auto-advance, pause on hover/focus, pagination dots,
 *      keyboard arrows, and no auto-advance when the user prefers reduced motion.
 * No Oracle branding (Q30).
 */
(function (apex, $) {
    "use strict";

    var BADGE_REFRESH_MS = 60000,
        SLIDE_MS = 7000;

    /* 1. Notification badge ------------------------------------------------ */
    function setBadge(count) {
        var $item = $(".oan-notif"),
            $badge = $item.find(".t-Button-badge"),
            text = count > 99 ? "99+" : (count > 0 ? String(count) : ""),
            label = count > 0 ? "Notifications, " + count + " unread" : "Notifications";
        $badge.text(text);
        $item.find("a, button").attr({ "title": label, "aria-label": label });
    }

    function refreshBadge() {
        if (document.hidden || !$(".oan-notif").length) {
            return;
        }
        apex.server.process("OAN_UNREAD_COUNT", {}, { dataType: "json" })
            .done(function (data) {
                if (data && typeof data.count === "number") {
                    setBadge(data.count);
                }
            });
        // A failed refresh keeps the last value; the next page view sets it again.
    }

    function initBadge() {
        if (!$(".oan-notif").length) {
            return;
        }
        var n = parseInt($(".oan-notif .t-Button-badge").text(), 10);
        setBadge(isNaN(n) ? 0 : n);
        window.setInterval(refreshBadge, BADGE_REFRESH_MS);
        document.addEventListener("visibilitychange", function () {
            if (!document.hidden) {
                refreshBadge();
            }
        });
    }

    /* 2. Profile card at the top of the left rail -------------------------- */
    function initProfileCard() {
        var $card = $("a.oan-profile-card").first(),
            $nav = $(".t-Body-nav").first();
        if ($card.length && $nav.length) {
            $card.prependTo($nav);
        }
    }

    /* 3. Global search ----------------------------------------------------- */
    function initSearch() {
        $(document).on("submit", "#oan-global-search", function (e) {
            var $form = $(this),
                q = $.trim($form.find("input[type=search]").val() || "")
                    .replace(/[:,\\]/g, " ")      // f?p separators
                    .substring(0, 200);
            e.preventDefault();
            if (q.length) {
                apex.navigation.redirect($form.data("url") + encodeURIComponent(q));
            }
        });
    }

    /* 4. Carousel ------------------------------------------------------------ */
    function initCarousel(root) {
        var $root = $(root),
            $slides = $root.find(".oan-slide"),
            $dots = $root.find(".oan-carousel-dot"),
            current = 0,
            timer = null,
            reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

        if ($slides.length < 2) {
            return;
        }

        function show(i) {
            current = (i + $slides.length) % $slides.length;
            $slides.attr("aria-hidden", "true").removeClass("is-active")
                .eq(current).attr("aria-hidden", "false").addClass("is-active");
            $dots.attr("aria-current", "false").eq(current).attr("aria-current", "true");
        }
        function stop() {
            window.clearInterval(timer);
            timer = null;
        }
        function start() {
            if (!reduceMotion && !timer) {
                timer = window.setInterval(function () { show(current + 1); }, SLIDE_MS);
            }
        }

        $dots.on("click", function () {
            show($dots.index(this));
        });
        $root.on("mouseenter focusin", stop)
             .on("mouseleave focusout", start)
             .on("keydown", function (e) {
                 if (e.key === "ArrowRight") { show(current + 1); }
                 if (e.key === "ArrowLeft") { show(current - 1); }
             });

        show(0);
        start();
    }

    $(function () {
        initBadge();
        initProfileCard();
        initSearch();
        $(".oan-carousel").each(function () { initCarousel(this); });
    });

})(apex, apex.jQuery);
