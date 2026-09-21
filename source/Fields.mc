// SPDX-License-Identifier: GPL-3.0-or-later
import Toybox.Lang;

// What a slot can show. A slot setting stores the row index, so rows are append-only:
// never reorder or remove one, or saved settings change meaning.
// tools/garmin-sitrep reads this table, so keep one row per line in this exact form.
module Fields {
    const NONE = 0;
    const DATE = 1;
    const STEPS = 2;
    const DISTANCE = 3;
    const CALORIES = 4;
    const FLOORS = 5;
    const ACTIVE_MIN = 6;
    const HEART_RATE = 7;
    const BODY_BATTERY = 8;
    const STRESS = 9;
    const ELEVATION = 10;
    const PRESSURE = 11;
    const TEMPERATURE = 12;
    const SUNRISE = 13;
    const SUNSET = 14;
    const BATTERY = 15;
    const BATTERY_DAYS = 16;
    const SOLAR = 17;
    const NOTIFICATIONS = 18;
    const ALARMS = 19;
    const WX_AGE = 20;
    const WEATHER = 21;

    // [cli name, text label, can fill an arc, icon letter in IconFont ("" = use the label)]
    const TABLE = [
        ["none", "", false, ""],
        ["date", "", false, ""],
        ["steps", "STP", true, "A"],
        ["distance", "DST", false, "B"],
        ["calories", "KCAL", false, "C"],
        ["floors", "FLR", true, "D"],
        ["active_min", "ACT", true, "E"],
        ["heart_rate", "HR", false, "F"],
        ["body_battery", "BB", true, "G"],
        ["stress", "STR", true, "H"],
        ["elevation", "ALT", false, "I"],
        ["pressure", "BAR", false, "J"],
        ["temperature", "TMP", false, "K"],
        ["sunrise", "RISE", false, "L"],
        ["sunset", "SET", false, "M"],
        ["battery", "BAT", true, "N"],
        ["battery_days", "BAT", false, "T"],
        ["solar", "SOL", true, "O"],
        ["notifications", "MSG", false, "P"],
        ["alarms", "ALM", false, "Q"],
        ["wx_age", "WX", false, "R"],
        ["weather", "WX", false, "R"]
    ];

    function label(id as Number) as String {
        return (id >= 0 && id < TABLE.size()) ? TABLE[id][1] as String : "";
    }

    function icon(id as Number) as String {
        return (id >= 0 && id < TABLE.size()) ? TABLE[id][3] as String : "";
    }
}
