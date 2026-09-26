// SPDX-License-Identifier: GPL-3.0-or-later
import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;

// Everything the faces read off the watch. Faces own the drawing and the wording;
// this module owns "what is the number, and is it even available on this device".
module HudData {

    // Light on the solar panel, 0-100 %, null on watches without solar.
    // This is intensity, not proof the battery is gaining: the watch can use more than it gets.
    function solarIntensity() as Number? {
        var stats = System.getSystemStats();
        if (!(stats has :solarIntensity)) {
            return null;
        }
        return stats.solarIntensity;
    }

    // Do Not Disturb, as the watch reports it to apps (false where unsupported).
    function dndActive() as Boolean {
        var settings = System.getDeviceSettings();
        return (settings has :doNotDisturb) && settings.doNotDisturb == true;
    }

    // 0 = nothing, 1 = last known, 2 = poor, 3 = usable, 4 = good.
    function gpsLevel() as Number {
        if (!(Toybox has :Position)) {
            return 0;
        }
        var info = Position.getInfo();
        if (info == null || info.accuracy == null) {
            return 0;
        }
        var quality = info.accuracy as Number;
        if (quality == Position.QUALITY_GOOD) {
            return 4;
        } else if (quality == Position.QUALITY_USABLE) {
            return 3;
        } else if (quality == Position.QUALITY_POOR) {
            return 2;
        } else if (quality == Position.QUALITY_LAST_KNOWN) {
            return 1;
        }
        return 0;
    }

    // The newest real sample from a SensorHistory iterator, or null when unsupported.
    // Looks back a few samples: the newest one is often empty between measurements.
    function sensorValue(which as Symbol) as Numeric? {
        if (!(Toybox has :SensorHistory)) {
            return null;
        }
        var options = {:period => 12, :order => SensorHistory.ORDER_NEWEST_FIRST};
        var iterator = null;
        if (which == :getBodyBatteryHistory && (SensorHistory has :getBodyBatteryHistory)) {
            iterator = SensorHistory.getBodyBatteryHistory(options);
        } else if (which == :getStressHistory && (SensorHistory has :getStressHistory)) {
            iterator = SensorHistory.getStressHistory(options);
        } else if (which == :getPressureHistory && (SensorHistory has :getPressureHistory)) {
            iterator = SensorHistory.getPressureHistory(options);
        } else if (which == :getElevationHistory && (SensorHistory has :getElevationHistory)) {
            iterator = SensorHistory.getElevationHistory(options);
        }
        if (iterator == null) {
            return null;
        }
        var sample = iterator.next();
        while (sample != null && sample.data == null) {
            sample = iterator.next();
        }
        if (sample == null) {
            return null;
        }
        return sample.data as Numeric;
    }

    function dateText() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return Lang.format("$1$ $2$ $3$", [
            (info.day_of_week as String).toUpper(),
            info.day,
            (info.month as String).toUpper()
        ]);
    }

    function timeText() as String {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour.format("%02d"), clock.min.format("%02d")]);
    }

    // Resting heart rate as the watch last worked it out (UserProfile, updated daily).
    function restingHeartRateText() as String {
        var profile = UserProfile.getProfile();
        if (profile has :restingHeartRate && profile.restingHeartRate != null) {
            return (profile.restingHeartRate as Number).toString();
        }
        return "--";
    }

    function heartRateText() as String {
        var info = Activity.getActivityInfo();
        if (info != null && info.currentHeartRate != null) {
            return (info.currentHeartRate as Number).toString();
        }
        if (ActivityMonitor has :getHeartRateHistory) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate.toString();
            }
        }
        return "--";
    }

    function stepsText() as String {
        var steps = ActivityMonitor.getInfo().steps;
        if (steps == null) {
            return "--";
        }
        return steps.toString();
    }

    function altitudeText() as String {
        var altitude = null;
        var info = Activity.getActivityInfo();
        if (info != null && info.altitude != null) {
            altitude = info.altitude;
        } else {
            altitude = sensorValue(:getElevationHistory);
        }
        if (altitude == null) {
            return "---M";
        }
        var metres = (altitude as Numeric).toNumber();
        if (System.getDeviceSettings().elevationUnits != System.UNIT_METRIC) {
            return ((metres * 3.28084).toNumber()).toString() + "FT";
        }
        return metres.toString() + "M";
    }

    function pressureText() as String {
        var pressure = sensorValue(:getPressureHistory);
        if (pressure == null) {
            return "----";
        }
        return ((pressure as Numeric) / 100.0 + 0.5).toNumber().toString() + "HPA";
    }
}
