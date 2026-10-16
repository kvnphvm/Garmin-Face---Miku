import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Weather;

// One snapshot of everything the watch face draws, refreshed once per update.
// Keeping the null handling and unit conversion here means the layout code
// only has to decide where things go, never whether they exist.
class WatchData {

    // Sunrise and sunset need a position. The weather service supplies one,
    // but only once the watch has synced; remembering the last known fix keeps
    // those two readouts populated in the meantime.
    private const STORED_LOCATION = "lastLocation";

    public var steps as Number = 0;
    public var stepGoal as Number = 0;
    public var battery as Number = 0;
    public var temperature as Number or Null = null;
    public var condition as String or Null = null;
    public var sunrise as Time.Moment or Null = null;
    public var sunset as Time.Moment or Null = null;

    private var _persistedLocation as Array or Null = null;

    function initialize() {
    }

    function refresh() as Void {
        readActivity();
        battery = System.getSystemStats().battery.toNumber();

        var conditions = Weather.getCurrentConditions();
        readWeather(conditions);
        readSunTimes(conditions);
    }

    // The goal is left at zero when the watch has not set one, which the face
    // reads as "show the count on its own".
    private function readActivity() as Void {
        steps = 0;
        stepGoal = 0;

        var info = ActivityMonitor.getInfo();
        if (info.steps != null) {
            steps = info.steps as Number;
        }
        if (info.stepGoal != null) {
            stepGoal = info.stepGoal as Number;
        }
    }

    private function readWeather(conditions as Weather.CurrentConditions or Null) as Void {
        temperature = null;
        condition = null;

        if (conditions == null) {
            return;
        }

        var celsius = conditions.temperature;
        if (celsius != null) {
            var value = celsius.toFloat();
            if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                value = value * 9.0 / 5.0 + 32.0;
            }
            temperature = Math.round(value).toNumber();
        }

        var code = conditions.condition;
        if (code != null) {
            condition = conditionLabel(code as Number);
        }
    }

    private function readSunTimes(conditions as Weather.CurrentConditions or Null) as Void {
        sunrise = null;
        sunset = null;

        var location = resolveLocation(conditions);
        if (location == null) {
            return;
        }

        var now = Time.now();
        sunrise = Weather.getSunrise(location, now);
        sunset = Weather.getSunset(location, now);
    }

    private function resolveLocation(
        conditions as Weather.CurrentConditions or Null
    ) as Position.Location or Null {
        var location = null;

        if (conditions != null) {
            location = conditions.observationLocationPosition;
        }
        if (location == null) {
            var activity = Activity.getActivityInfo();
            if (activity != null) {
                location = activity.currentLocation;
            }
        }

        if (location != null) {
            rememberLocation(location as Position.Location);
            return location as Position.Location;
        }

        return recallLocation();
    }

    // Storage writes hit flash, so only persist when the fix actually moves.
    private function rememberLocation(location as Position.Location) as Void {
        var degrees = location.toDegrees();
        if (_persistedLocation != null && sameLocation(_persistedLocation as Array, degrees)) {
            return;
        }
        Application.Storage.setValue(STORED_LOCATION, degrees);
        _persistedLocation = degrees;
    }

    private function sameLocation(a as Array, b as Array) as Boolean {
        if (a.size() < 2 || b.size() < 2) {
            return false;
        }
        return (a[0] as Double) == (b[0] as Double)
            && (a[1] as Double) == (b[1] as Double);
    }

    private function recallLocation() as Position.Location or Null {
        var saved = Application.Storage.getValue(STORED_LOCATION);
        if (!(saved instanceof Array) || (saved as Array).size() < 2) {
            return null;
        }
        var degrees = saved as Array;
        return new Position.Location({
            :latitude => degrees[0],
            :longitude => degrees[1],
            :format => :degrees
        });
    }

    // The API defines 53 conditions; collapse them into labels that fit the
    // width available next to the temperature.
    private function conditionLabel(code as Number) as String {
        switch (code) {
            case Weather.CONDITION_CLEAR:
            case Weather.CONDITION_MOSTLY_CLEAR:
            case Weather.CONDITION_PARTLY_CLEAR:
            case Weather.CONDITION_FAIR:
                return "CLEAR";

            case Weather.CONDITION_PARTLY_CLOUDY:
            case Weather.CONDITION_THIN_CLOUDS:
                return "PART CLOUD";

            case Weather.CONDITION_CLOUDY:
            case Weather.CONDITION_MOSTLY_CLOUDY:
                return "CLOUDY";

            case Weather.CONDITION_RAIN:
            case Weather.CONDITION_LIGHT_RAIN:
            case Weather.CONDITION_HEAVY_RAIN:
            case Weather.CONDITION_DRIZZLE:
            case Weather.CONDITION_FREEZING_RAIN:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN:
            case Weather.CONDITION_UNKNOWN_PRECIPITATION:
                return "RAIN";

            case Weather.CONDITION_SHOWERS:
            case Weather.CONDITION_LIGHT_SHOWERS:
            case Weather.CONDITION_HEAVY_SHOWERS:
            case Weather.CONDITION_SCATTERED_SHOWERS:
            case Weather.CONDITION_CHANCE_OF_SHOWERS:
                return "SHOWERS";

            case Weather.CONDITION_THUNDERSTORMS:
            case Weather.CONDITION_SCATTERED_THUNDERSTORMS:
            case Weather.CONDITION_CHANCE_OF_THUNDERSTORMS:
            case Weather.CONDITION_SQUALL:
            case Weather.CONDITION_TROPICAL_STORM:
                return "STORM";

            case Weather.CONDITION_SNOW:
            case Weather.CONDITION_LIGHT_SNOW:
            case Weather.CONDITION_HEAVY_SNOW:
            case Weather.CONDITION_FLURRIES:
            case Weather.CONDITION_CHANCE_OF_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_SNOW:
                return "SNOW";

            case Weather.CONDITION_RAIN_SNOW:
            case Weather.CONDITION_LIGHT_RAIN_SNOW:
            case Weather.CONDITION_HEAVY_RAIN_SNOW:
            case Weather.CONDITION_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_CLOUDY_CHANCE_OF_RAIN_SNOW:
            case Weather.CONDITION_WINTRY_MIX:
            case Weather.CONDITION_SLEET:
            case Weather.CONDITION_ICE:
            case Weather.CONDITION_ICE_SNOW:
            case Weather.CONDITION_HAIL:
                return "WINTRY";

            case Weather.CONDITION_FOG:
            case Weather.CONDITION_MIST:
                return "FOG";

            case Weather.CONDITION_HAZE:
            case Weather.CONDITION_HAZY:
            case Weather.CONDITION_SMOKE:
            case Weather.CONDITION_DUST:
            case Weather.CONDITION_SAND:
            case Weather.CONDITION_VOLCANIC_ASH:
                return "HAZE";

            case Weather.CONDITION_WINDY:
            case Weather.CONDITION_SANDSTORM:
                return "WINDY";

            case Weather.CONDITION_HURRICANE:
            case Weather.CONDITION_TORNADO:
                return "SEVERE";

            default:
                return "--";
        }
    }
}
