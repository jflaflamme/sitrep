// SPDX-License-Identifier: GPL-3.0-or-later
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class SitrepApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new SitrepView();
        return [view, new SitrepDelegate(view)];
    }

    // a new settings file from tools/garmin-sitrep or a phone takes effect at once
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}

// Tells the view when the watch stops partial updates for using too much power.
class SitrepDelegate extends WatchUi.WatchFaceDelegate {
    private var _view as SitrepView;

    function initialize(view as SitrepView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPowerBudgetExceeded(powerInfo as WatchUi.WatchFacePowerInfo) as Void {
        _view.budgetExceeded();
    }
}
