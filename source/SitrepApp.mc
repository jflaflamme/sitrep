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

    // On the watch: the face's Customize menu. Shows the version, so an update (over USB or
    // through a phone app) can be confirmed on the watch; the layout itself is set with
    // tools/garmin-sitrep.
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        var menu = new WatchUi.Menu2({:title => "SITREP"});
        menu.addItem(new WatchUi.MenuItem("Version",
            WatchUi.loadResource(Rez.Strings.AppVersion) as String, :version, {}));
        menu.addItem(new WatchUi.MenuItem("Layout", "set with garmin-sitrep", :layout, {}));
        return [menu, new WatchUi.Menu2InputDelegate()];
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
