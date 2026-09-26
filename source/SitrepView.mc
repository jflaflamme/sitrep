// SPDX-License-Identifier: GPL-3.0-or-later
import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;
import Toybox.Weather;
import Toybox.WatchUi;

// SITREP: one screen of status. An arc over the top and under the bottom, a line of data
// above and below two rows of two, the time in the middle. What each place shows is a
// setting (resources/settings/properties.xml), changed from a computer with
// tools/garmin-sitrep. Geometry is designed on a 280 px round screen and scaled.
class SitrepView extends WatchUi.WatchFace {

    // Garmin's own bold fonts: drawn for this screen, far heavier than a custom bitmap font.
    private const LABEL_FONT = Graphics.FONT_XTINY;
    private const VALUE_FONT = Graphics.FONT_SMALL;
    private const TIME_FONT = Graphics.FONT_NUMBER_HOT;
    private const SUB_FONT = Graphics.FONT_TINY;

    // Memory-in-pixel screens reflect light instead of emitting it: only full-strength
    // colours stay readable. Set per update from the "light" setting.
    private var _bg as Number = Graphics.COLOR_BLACK;
    private var _text as Number = Graphics.COLOR_WHITE;
    private var _track as Number = 0xAAAAAA;
    private var _label as Number = 0xFFAA00;
    private var _accent as Number = 0xFFAA00;
    private var _awake as Boolean = true;
    private var _iconFont as FontResource?;

    // seconds redrawn once a second in low power (onPartialUpdate), inside this box
    private var _secX as Number = 0;
    private var _secY as Number = 0;
    private var _secBox as Array<Number> = [0, 0, 0, 0];
    private var _budgetExceeded as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _iconFont = WatchUi.loadResource(Rez.Fonts.IconFont) as FontResource;
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var width = dc.getWidth();
        var cx = width / 2;
        var cy = dc.getHeight() / 2;
        var s = width / 280.0;

        _accent = setting("accent_color", 0xFFAA00) as Number;
        if (setting("light", false) as Boolean) {
            // black on white: the most readable combination on a reflective screen in daylight
            _bg = Graphics.COLOR_WHITE;
            _text = Graphics.COLOR_BLACK;
            _track = 0x555555;
            _label = Graphics.COLOR_BLACK;
        } else {
            _bg = Graphics.COLOR_BLACK;
            _text = setting("time_color", Graphics.COLOR_WHITE) as Number;
            _track = 0xAAAAAA;
            _label = _accent;
        }

        dc.setColor(_bg, _bg);
        dc.clear();

        if (setting("dnd_blank", true) as Boolean && HudData.dndActive()) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            return;
        }

        drawArc(dc, cx, cy, s, setting("arc_top", Fields.BODY_BATTERY) as Number, true);
        drawArc(dc, cx, cy, s, setting("arc_bottom", Fields.BATTERY) as Number, false);
        if (setting("easter_eggs", true) as Boolean) {
            drawUfo(dc, cx, s);
        }

        // Fixed line centres on the 280 px design. Not spaced by getFontHeight(): the
        // number fonts report far more height than their digits use (seen on the watch:
        // the stacked layout pushed the last two lines off the bottom).
        // (the small line under the time sits at 162, not 168: at 168 the message count
        // crowded the heart rate row below, seen on the watch in 0.2.0)
        var ys = [scale(50, s), scale(80, s), scale(128, s), scale(162, s), scale(196, s), scale(226, s)];

        // widest a field may draw: the side columns are 120 px apart, the lines above and
        // below have the width of the circle at their height
        var side = scale(60, s);
        var sideMax = scale(112, s);
        var lineMax = scale(200, s);
        drawField(dc, cx, ys[0], setting("top", Fields.DATE) as Number, lineMax);
        drawField(dc, cx - side, ys[1], setting("left1", Fields.ELEVATION) as Number, sideMax);
        drawField(dc, cx + side, ys[1], setting("right1", Fields.CALORIES) as Number, sideMax);
        drawTime(dc, cx, ys[2], ys[3], s);
        drawField(dc, cx - side, ys[4], setting("left2", Fields.HEART_RATE) as Number, sideMax);
        drawField(dc, cx + side, ys[4], setting("right2", Fields.STEPS) as Number, sideMax);
        drawField(dc, cx, ys[5], setting("bottom", Fields.BATTERY) as Number, lineMax);
    }

    // --- layout pieces ------------------------------------------------------------

    private function drawTime(dc as Dc, cx as Number, y as Number, subY as Number, s as Float) as Void {
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var time = HudData.timeText();

        // seconds sit right of the minutes, low beside the digits; time and seconds are
        // centred together so the pair stays balanced
        var gap = scale(4, s);
        var secW = dc.getTextWidthInPixels("00", SUB_FONT);
        var timeW = dc.getTextWidthInPixels(time, TIME_FONT);
        var withSeconds = setting("seconds", true) as Boolean;
        var timeX = withSeconds ? cx - (secW + gap) / 2 : cx;
        dc.setColor(_text, Graphics.COLOR_TRANSPARENT);
        dc.drawText(timeX, y, TIME_FONT, time, center);

        // one line under the time: notification count (or the ghost) left
        var eggs = setting("easter_eggs", true) as Boolean;
        var device = System.getDeviceSettings();
        if (eggs && !device.phoneConnected) {
            drawIcon(dc, cx - scale(56, s), subY, "c");   // ghost: phone out of reach
        } else if (setting("notifications", true) as Boolean) {
            var count = device.notificationCount;
            if (count != null && count > 0) {
                drawPair(dc, cx - scale(56, s), subY, "P", count.toString(), SUB_FONT, scale(80, s));
            }
        }
        _secX = timeX + timeW / 2 + gap + secW / 2;
        _secY = y + scale(10, s);
        var w = secW + scale(6, s);
        var h = dc.getFontHeight(SUB_FONT);
        _secBox = [_secX - w / 2, _secY - h / 2, w, h];
        if (showSeconds()) {
            dc.setColor(_text, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_secX, _secY, SUB_FONT, System.getClockTime().sec.format("%02d"), center);
        }
        // centre: skull on a nearly empty battery, else the sun in light, else the moon at night
        var solar = HudData.solarIntensity();
        if (eggs && System.getSystemStats().battery < 10) {
            drawIcon(dc, cx, subY, "b");
        } else if (setting("solar_icon", true) as Boolean && solar != null && solar > 0) {
            drawSun(dc, cx, subY, s);
        } else if (eggs && isNight()) {
            drawIcon(dc, cx, subY, "d");
        }
    }

    // UFO over the top arc at 11:11, 22:22, 3:33 and 15:33
    private function drawUfo(dc as Dc, cx as Number, s as Float) as Void {
        var clock = System.getClockTime();
        var h = clock.hour;
        var m = clock.min;
        if ((h == 11 && m == 11) || (h == 22 && m == 22) || (h % 12 == 3 && m == 33)) {
            drawIcon(dc, cx, scale(24, s), "Z");
        }
    }

    private function drawIcon(dc as Dc, x as Number, y as Number, letter as String) as Void {
        dc.setColor(_label, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _iconFont as FontResource, letter,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Night between today's sunset and sunrise at the last known position; 18:00 to 06:00
    // when the watch has no position or weather yet.
    private function isNight() as Boolean {
        var now = Time.now();
        var where = lastPosition();
        if (where != null && (Weather has :getSunrise)) {
            var rise = Weather.getSunrise(where, now);
            var set = Weather.getSunset(where, now);
            if (rise != null && set != null) {
                return now.lessThan(rise) || now.greaterThan(set);
            }
        }
        var hour = System.getClockTime().hour;
        return hour < 6 || hour >= 18;
    }

    private function showSeconds() as Boolean {
        if (!(setting("seconds", true) as Boolean)) {
            return false;
        }
        if (_awake) {
            return true;
        }
        return setting("seconds_always", true) as Boolean && !_budgetExceeded;
    }

    // Low power: the watch calls this once a second; only the seconds box is redrawn.
    function onPartialUpdate(dc as Dc) as Void {
        if (!showSeconds() || (setting("dnd_blank", true) as Boolean && HudData.dndActive())) {
            return;
        }
        dc.setClip(_secBox[0], _secBox[1], _secBox[2], _secBox[3]);
        dc.setColor(_bg, _bg);
        dc.clear();
        dc.setColor(_text, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_secX, _secY, SUB_FONT, System.getClockTime().sec.format("%02d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.clearClip();
    }

    // The watch stops partial updates when a face uses too much power; hide seconds then.
    function budgetExceeded() as Void {
        _budgetExceeded = true;
        WatchUi.requestUpdate();
    }

    // Sun between the notification count and the seconds, while the panel gets light.
    // The watch reports light on the panel, not whether the battery is actually gaining.
    private function drawSun(dc as Dc, x as Number, y as Number, s as Float) as Void {
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, scale(5, s));
        dc.setPenWidth(scale(2, s));
        var inner = scale(8, s);
        var outer = scale(12, s);
        for (var deg = 0; deg < 360; deg += 45) {
            var rad = Math.toRadians(deg);
            var cos = Math.cos(rad);
            var sin = Math.sin(rad);
            dc.drawLine(x + (inner * cos).toNumber(), y - (inner * sin).toNumber(),
                        x + (outer * cos).toNumber(), y - (outer * sin).toNumber());
        }
    }

    private function drawField(dc as Dc, x as Number, y as Number, id as Number,
                               maxWidth as Number) as Void {
        var value = fieldValue(id);
        if (value == null) {
            return;
        }
        // a field may pick its own icon (weather: the current condition)
        var icon = value.size() > 2 && value[2] != null ? value[2] as String : Fields.icon(id);
        // and a shorter text for when the full one is too wide (counts: 12.3K)
        var text = value[0] as String;
        if (value.size() > 3 && value[3] != null) {
            var full = labelled(dc, icon.length() > 0 ? icon : Fields.label(id), text, VALUE_FONT);
            if (full > maxWidth) {
                text = value[3] as String;
            }
        }
        drawPair(dc, x, y, icon.length() > 0 ? icon : Fields.label(id), text, VALUE_FONT, maxWidth);
    }

    // icon (one letter of IconFont) or small text label, then the value, centred together on x.
    // Wider than maxWidth, the value drops to SUB_FONT; still too wide, the label goes too.
    private function drawPair(dc as Dc, x as Number, y as Number, label as String, text as String,
                              valueFont as FontDefinition, maxWidth as Number) as Void {
        var labelFont = labelFontFor(label);
        var gap = label.length() > 0 ? 4 : 0;
        var labelWidth = label.length() > 0 ? dc.getTextWidthInPixels(label, labelFont) : 0;
        var total = labelWidth + gap + dc.getTextWidthInPixels(text, valueFont);
        if (total > maxWidth && valueFont != SUB_FONT) {
            valueFont = SUB_FONT;
            total = labelWidth + gap + dc.getTextWidthInPixels(text, valueFont);
        }
        if (total > maxWidth && labelWidth > 0) {
            gap = 0;
            labelWidth = 0;
            total = dc.getTextWidthInPixels(text, valueFont);
        }
        var left = x - total / 2;
        var vcenter = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        if (labelWidth > 0) {
            dc.setColor(_label, Graphics.COLOR_TRANSPARENT);
            dc.drawText(left, y, labelFont, label, vcenter);
        }
        dc.setColor(_text, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + labelWidth + gap, y, valueFont, text, vcenter);
    }

    // width drawPair gives label and text before any fitting
    private function labelled(dc as Dc, label as String, text as String, valueFont as FontDefinition) as Number {
        var labelWidth = label.length() > 0 ? dc.getTextWidthInPixels(label, labelFontFor(label)) + 4 : 0;
        return labelWidth + dc.getTextWidthInPixels(text, valueFont);
    }

    private function labelFontFor(label as String) as FontType {
        return (label.length() == 1 ? _iconFont : LABEL_FONT) as FontType;
    }

    // Top arc spans 150 to 30 degrees over the top, bottom arc 210 to 330 under the bottom;
    // both fill from the left. Only fields with a fraction (Fields.TABLE column 3) fill.
    private function drawArc(dc as Dc, cx as Number, cy as Number, s as Float, id as Number,
                             top as Boolean) as Void {
        if (id == Fields.NONE) {
            return;
        }
        var r = scale(130, s);
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);   // smooth arc edges; the arcs were visibly stepped without
        }
        dc.setColor(_track, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(scale(3, s));
        if (top) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 150, 30);
        } else {
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 210, 330);
        }

        var value = fieldValue(id);
        if (value == null || value[1] == null) {
            return;
        }
        var fraction = value[1] as Float;
        if (fraction > 1.0) {
            fraction = 1.0;
        }
        var sweep = (120 * fraction).toNumber();
        if (sweep < 1) {
            return; // start == end would draw a full circle
        }
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(scale(8, s));
        if (top) {
            dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 150, 150 - sweep);
        } else {
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, 210, 210 + sweep);
        }
    }

    // --- data ---------------------------------------------------------------------

    // [text, fraction 0..1 or null, own icon or null, shorter text or null], or null for an
    // empty slot; the last two may be left out
    private function fieldValue(id as Number) as Array? {
        var monitor = ActivityMonitor.getInfo();
        var settings = System.getDeviceSettings();
        var stats = System.getSystemStats();

        if (id == Fields.DATE) {
            var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            return [(info.day_of_week as String).toUpper() + " " + info.day, null];
        } else if (id == Fields.STEPS) {
            // rocket once the step goal is reached
            var done = eggs() && monitor.steps != null && monitor.stepGoal != null
                && monitor.stepGoal > 0 && monitor.steps >= monitor.stepGoal;
            return [orDash(monitor.steps), ratio(monitor.steps, monitor.stepGoal), done ? "e" : null,
                    compact(monitor.steps)];
        } else if (id == Fields.DISTANCE) {
            if (monitor.distance == null) {
                return ["--", null];
            }
            var km = (monitor.distance as Number) / 100000.0;
            if (settings.distanceUnits == System.UNIT_STATUTE) {
                return [(km / 1.609344).format("%.1f") + "MI", null];
            }
            return [km.format("%.1f") + "KM", null];
        } else if (id == Fields.CALORIES) {
            return [orDash(monitor.calories), null, null, compact(monitor.calories)];
        } else if (id == Fields.FLOORS) {
            if (!(monitor has :floorsClimbed)) {
                return ["--", null];
            }
            return [orDash(monitor.floorsClimbed), ratio(monitor.floorsClimbed, monitor.floorsClimbedGoal)];
        } else if (id == Fields.ACTIVE_MIN) {
            if (!(monitor has :activeMinutesWeek) || monitor.activeMinutesWeek == null) {
                return ["--", null];
            }
            var total = (monitor.activeMinutesWeek as ActivityMonitor.ActiveMinutes).total;
            return [orDash(total), ratio(total, monitor.activeMinutesWeekGoal)];
        } else if (id == Fields.HEART_RATE) {
            // alien at exactly 111 bpm, or in the top heart rate zone
            var text = HudData.heartRateText();
            var bpm = text.toNumber();
            var alien = eggs() && bpm != null && (bpm == 111 || bpm >= topZoneStart());
            return [text, null, alien ? "a" : null];
        } else if (id == Fields.RESTING_HR) {
            return [HudData.restingHeartRateText(), null];
        } else if (id == Fields.BODY_BATTERY) {
            return percent(HudData.sensorValue(:getBodyBatteryHistory));
        } else if (id == Fields.STRESS) {
            return percent(HudData.sensorValue(:getStressHistory));
        } else if (id == Fields.ELEVATION) {
            // satellite while the watch holds a usable GPS fix under 10 minutes old
            return [HudData.altitudeText(), null, eggs() && freshFix() ? "f" : null];
        } else if (id == Fields.PRESSURE) {
            return [HudData.pressureText(), null];
        } else if (id == Fields.TEMPERATURE) {
            return [temperatureText(settings), null];
        } else if (id == Fields.SUNRISE) {
            return [sunText(true), null];
        } else if (id == Fields.SUNSET) {
            return [sunText(false), null];
        } else if (id == Fields.BATTERY) {
            return [(stats.battery + 0.5).toNumber().toString() + "%", stats.battery / 100.0,
                    eggs() && stats.battery < 10 ? "b" : null];
        } else if (id == Fields.BATTERY_DAYS) {
            if (!(stats has :batteryInDays)) {
                return ["--", null];
            }
            return [(stats.batteryInDays + 0.5).toNumber().toString() + "D", null];
        } else if (id == Fields.SOLAR) {
            var solar = HudData.solarIntensity();
            return solar == null ? ["--", null] : [solar.toString() + "%", solar / 100.0];
        } else if (id == Fields.NOTIFICATIONS) {
            return [orDash(settings.notificationCount), null];
        } else if (id == Fields.ALARMS) {
            return [orDash(settings.alarmCount), null];
        } else if (id == Fields.WX_AGE) {
            return [weatherAge(), null];
        } else if (id == Fields.WEATHER) {
            return weatherNow(settings);
        }
        return null;
    }

    private function temperatureText(settings as System.DeviceSettings) as String {
        var celsius = null;
        if (Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null && conditions.temperature != null) {
                celsius = conditions.temperature;
            }
        }
        if (celsius == null && (SensorHistory has :getTemperatureHistory)) {
            var sample = SensorHistory.getTemperatureHistory({:period => 1}).next();
            if (sample != null && sample.data != null) {
                celsius = sample.data; // the watch's own sensor, warmed by the wrist
            }
        }
        if (celsius == null) {
            return "--";
        }
        if (settings.temperatureUnits == System.UNIT_STATUTE) {
            return ((celsius as Numeric) * 9 / 5.0 + 32 + 0.5).toNumber().toString() + "°F";
        }
        return ((celsius as Numeric) + 0.5).toNumber().toString() + "°C";
    }

    // Current conditions from the phone: condition icon plus temperature, "--" before any arrive.
    private function weatherNow(settings as System.DeviceSettings) as Array {
        if (!(Toybox has :Weather)) {
            return ["--", null];
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null || conditions.temperature == null) {
            return ["--", null];
        }
        var celsius = conditions.temperature as Numeric;
        var text = settings.temperatureUnits == System.UNIT_STATUTE
            ? (celsius * 9 / 5.0 + 32 + 0.5).toNumber().toString() + "°"
            : (celsius + 0.5).toNumber().toString() + "°";
        return [text, null, conditionIcon(conditions.condition)];
    }

    // Letters of IconFont (make_icons.py): O sun, R cloud, U rain, V storm, W fog, X snow, Y wind
    private function conditionIcon(condition as Number?) as String {
        if (condition == null) {
            return "R";
        }
        var sun = [Weather.CONDITION_CLEAR, Weather.CONDITION_MOSTLY_CLEAR, Weather.CONDITION_PARTLY_CLEAR,
                   Weather.CONDITION_FAIR];
        var rain = [Weather.CONDITION_RAIN, Weather.CONDITION_LIGHT_RAIN, Weather.CONDITION_HEAVY_RAIN,
                    Weather.CONDITION_SHOWERS, Weather.CONDITION_LIGHT_SHOWERS, Weather.CONDITION_HEAVY_SHOWERS,
                    Weather.CONDITION_SCATTERED_SHOWERS, Weather.CONDITION_CHANCE_OF_SHOWERS,
                    Weather.CONDITION_DRIZZLE, Weather.CONDITION_UNKNOWN_PRECIPITATION];
        var storm = [Weather.CONDITION_THUNDERSTORMS, Weather.CONDITION_SCATTERED_THUNDERSTORMS,
                     Weather.CONDITION_CHANCE_OF_THUNDERSTORMS, Weather.CONDITION_TORNADO,
                     Weather.CONDITION_HURRICANE, Weather.CONDITION_TROPICAL_STORM, Weather.CONDITION_SQUALL];
        var fog = [Weather.CONDITION_FOG, Weather.CONDITION_MIST, Weather.CONDITION_HAZY, Weather.CONDITION_HAZE,
                   Weather.CONDITION_SMOKE, Weather.CONDITION_DUST, Weather.CONDITION_SAND,
                   Weather.CONDITION_SANDSTORM, Weather.CONDITION_VOLCANIC_ASH];
        var snow = [Weather.CONDITION_SNOW, Weather.CONDITION_LIGHT_SNOW, Weather.CONDITION_HEAVY_SNOW,
                    Weather.CONDITION_WINTRY_MIX, Weather.CONDITION_RAIN_SNOW, Weather.CONDITION_LIGHT_RAIN_SNOW,
                    Weather.CONDITION_HEAVY_RAIN_SNOW, Weather.CONDITION_HAIL, Weather.CONDITION_ICE,
                    Weather.CONDITION_FLURRIES, Weather.CONDITION_SLEET, Weather.CONDITION_FREEZING_RAIN];
        if (sun.indexOf(condition) >= 0) {
            return "O";
        } else if (rain.indexOf(condition) >= 0) {
            return "U";
        } else if (storm.indexOf(condition) >= 0) {
            return "V";
        } else if (fog.indexOf(condition) >= 0) {
            return "W";
        } else if (snow.indexOf(condition) >= 0) {
            return "X";
        } else if (condition == Weather.CONDITION_WINDY) {
            return "Y";
        }
        return "R";
    }

    // How long ago the watch last received weather from the phone: "NONE" if it never has.
    // A way to check the phone's weather service from the watch itself.
    private function weatherAge() as String {
        if (!(Toybox has :Weather)) {
            return "N/A";
        }
        var conditions = Weather.getCurrentConditions();
        if (conditions == null) {
            return "NONE";
        }
        if (conditions.observationTime == null) {
            return "?";
        }
        var seconds = Time.now().subtract(conditions.observationTime as Time.Moment).value();
        if (seconds < 3600) {
            return (seconds / 60).toString() + "M";
        } else if (seconds < 86400) {
            return (seconds / 3600).toString() + "H";
        }
        return (seconds / 86400).toString() + "D";
    }

    // Today's sunrise or sunset at the last known position (API 3.3; "--" before).
    private function sunText(rise as Boolean) as String {
        if (!(Toybox has :Weather) || !(Weather has :getSunrise)) {
            return "--";
        }
        var where = lastPosition();
        if (where == null) {
            return "--";
        }
        var moment = rise ? Weather.getSunrise(where, Time.now()) : Weather.getSunset(where, Time.now());
        if (moment == null) {
            return "--";
        }
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return info.hour.format("%02d") + ":" + info.min.format("%02d");
    }

    // --- helpers ------------------------------------------------------------------

    private function eggs() as Boolean {
        return setting("easter_eggs", true) as Boolean;
    }

    private function lastPosition() as Position.Location? {
        var activity = Activity.getActivityInfo();
        if (activity != null && activity.currentLocation != null) {
            return activity.currentLocation;
        }
        if (Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                return conditions.observationLocationPosition;
            }
        }
        return null;
    }

    private function freshFix() as Boolean {
        var info = Position.getInfo();
        if (info == null || info.accuracy == null || info.when == null) {
            return false;
        }
        return info.accuracy >= Position.QUALITY_USABLE
            && Time.now().subtract(info.when as Time.Moment).value() < 600;
    }

    // Lower bound of the user's top heart rate zone (zone 5), from the watch's user profile.
    private function topZoneStart() as Number {
        var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
        if (zones == null || zones.size() < 5) {
            return 999;
        }
        return zones[4] as Number;
    }

    private function setting(key as String, fallback as PropertyValueType) as PropertyValueType {
        try {
            var value = Properties.getValue(key);
            return value == null ? fallback : value;
        } catch (e) {
            return fallback;
        }
    }

    private function orDash(value as Numeric?) as String {
        return value == null ? "--" : value.toNumber().toString();
    }

    // A count in thousands, the way Garmin's own faces do: 1.2K, 12.3K, 123K
    // (drawField uses it only when the full number does not fit its place).
    private function compact(value as Numeric?) as String? {
        if (value == null || value < 1000) {
            return null;
        }
        var thousands = value / 1000.0;
        if (thousands < 100) {
            return (((thousands * 10).toNumber()) / 10.0).format("%.1f") + "K";
        }
        return thousands.toNumber().toString() + "K";
    }

    private function ratio(value as Numeric?, goal as Numeric?) as Float? {
        if (value == null || goal == null || goal <= 0) {
            return null;
        }
        return value.toFloat() / goal;
    }

    private function percent(value as Numeric?) as Array {
        if (value == null) {
            return ["--", null];
        }
        return [value.toNumber().toString() + "%", value / 100.0];
    }

    private function scale(value as Numeric, s as Float) as Number {
        return (value * s + 0.5).toNumber();
    }
}
