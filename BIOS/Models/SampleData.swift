import Foundation

/// Invented example data in the shape of `/v1/dashboard` and `/v1/series`.
/// Used only by Debug builds without a server config (simulator), but compiled
/// in every configuration so the compile check covers it. This repo is public:
/// every value here is made up, none is a real health measurement.
enum SampleData {
    /// The server's example document (docs/fixtures/dashboard.example.json in
    /// the BIOS repo, invented values, scenario "Infektmuster Tag 3").
    static func dashboard() -> JSONValue? {
        guard let data = dashboardFixture.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Smooth invented curve per metric with a baseline band.
    static func series(metric: String, days: Int, now: Date = Date()) -> JSONValue? {
        let calendar = Calendar.current
        let hourly = metric == "glucose" || metric == "iob"
        let weekly = metric.hasPrefix("ww_")
        let count = hourly ? 24 * max(1, min(days, 7)) : weekly ? max(4, days / 7) : max(1, days)
        let (center, amplitude, band): (Double, Double, Bool) = {
            switch metric {
            case "whoop_rhr": return (56, 2, true)
            case "whoop_hrv": return (68, 8, true)
            case "whoop_recovery": return (62, 25, false)
            case "whoop_sleep_duration": return (7.2, 0.7, true)
            case "whoop_skin_temp": return (0, 0.15, true)
            case "whoop_resp_rate": return (15.2, 0.3, true)
            case "glucose": return (140, 40, false)
            case "glucose_daily": return (138, 8, true)
            case "tdd": return (36, 3, true)
            case "ins_per_10g": return (1.0, 0.07, true)
            case "ins_auto": return (5.6, 1.4, false)
            case "iob": return (1.5, 1.2, false)
            case "pollen_grass": return (3, 1.5, false)
            case "pollen_birch": return (0.5, 0.5, false)
            default: return weekly ? (20, 18, false) : (50, 10, false)
            }
        }()
        var points: [JSONValue] = []
        for index in 0..<count {
            let back = count - 1 - index
            let date: Date
            let stamp: String
            if hourly {
                date = calendar.date(byAdding: .hour, value: -back, to: now) ?? now
                let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                stamp = String(format: "%04d-%02d-%02dT%02d:00:00", parts.year ?? 2026, parts.month ?? 1,
                               parts.day ?? 1, parts.hour ?? 0)
            } else {
                date = calendar.date(byAdding: .day, value: -(weekly ? back * 7 : back), to: now) ?? now
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                stamp = String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
            }
            let wave = sin(Double(index) * 0.9) * 0.6 + sin(Double(index) * 0.37) * 0.4
            var value = center + amplitude * wave
            if metric == "whoop_recovery" || metric.hasPrefix("pollen") || metric == "iob" || weekly {
                value = max(0, value)
            }
            if metric == "tir" {
                let tir = (78 + 6 * wave).rounded()
                let tbr = 2.0
                points.append(.object(["t": .string(stamp), "v": .number(tir), "tbr": .number(tbr),
                                       "tir": .number(tir), "tar": .number(100 - tir - tbr)]))
            } else {
                points.append(.object(["t": .string(stamp), "v": .number((value * 100).rounded() / 100)]))
            }
        }
        var object: [String: JSONValue] = [
            "metric": .string(metric),
            "resolution": .string(hourly ? "hour" : weekly ? "week" : "day"),
            "days": .number(Double(days)),
            "points": .array(points),
        ]
        if band {
            let sigma = amplitude / 2
            object["baseline"] = .object([
                "median": .number(center), "sigma": .number(sigma),
                "lo": .number(center - 1.5 * sigma), "hi": .number(center + 1.5 * sigma),
                "n": .number(28), "z": .number(1.5),
            ])
        }
        return .object(object)
    }

    private static let dashboardFixture = #"""
    {
      "schema_version": 1,
      "generated_at": "2026-09-25T13:30:00+02:00",
      "today": "2026-09-25",
      "freshness": [
        {
          "source": "whoop",
          "label": "Whoop",
          "last": "2026-09-25T07:47:00+02:00",
          "age_min": 343,
          "status": "ok",
          "stale_after_min": 2160,
          "cadence": "stündlich",
          "note": null
        },
        {
          "source": "dexcom_share",
          "label": "Dexcom Share",
          "last": "2026-09-25T13:15:00+02:00",
          "age_min": 15,
          "status": "ok",
          "stale_after_min": 120,
          "cadence": "stündlich",
          "note": null
        },
        {
          "source": "loop",
          "label": "Loop (Nightscout)",
          "last": "2026-09-25T13:15:20+02:00",
          "age_min": 14,
          "status": "ok",
          "stale_after_min": 120,
          "cadence": "stündlich",
          "note": null
        },
        {
          "source": "abwasser_wien",
          "label": "Abwasser Wien",
          "last": "2026-09-20",
          "age_min": 8010,
          "status": "ok",
          "stale_after_min": 30240,
          "cadence": "wöchentlich",
          "note": null
        },
        {
          "source": "abwasser_de",
          "label": "Abwasser Deutschland",
          "last": "2026-09-20",
          "age_min": 8010,
          "status": "ok",
          "stale_after_min": 30240,
          "cadence": "wöchentlich",
          "note": null
        },
        {
          "source": "pollen",
          "label": "Pollen",
          "last": "2026-09-24",
          "age_min": 2250,
          "status": "ok",
          "stale_after_min": 4320,
          "cadence": "täglich",
          "note": null
        },
        {
          "source": "whoop_check",
          "label": "Infekt-Check",
          "last": "2026-09-25T13:25:00+02:00",
          "age_min": 5,
          "status": "ok",
          "stale_after_min": 1200,
          "cadence": "13:25 und 20:25",
          "note": null
        },
        {
          "source": "outlook",
          "label": "Ausblick",
          "last": "2026-09-25T06:40:00+02:00",
          "age_min": 410,
          "status": "ok",
          "stale_after_min": 840,
          "cadence": "06:40 und 18:40",
          "note": null
        }
      ],
      "infection": {
        "day": "2026-09-25",
        "checked_at": "2026-09-25T13:25:00+02:00",
        "evaluable": true,
        "reason": null,
        "status": "warn",
        "kind": "infekt",
        "headline": "Infektmuster Tag 3",
        "subline": "Ruhepuls hoch und HRV tief seit Mi 23.09, dazu Hauttemperatur erhöht, Atemfrequenz erhöht.",
        "episode_day": 3,
        "since": "2026-09-23",
        "alerts": [
          {
            "kind": "infekt",
            "severity": "warn",
            "text": "Infektmuster seit 3 Tagen (ab 23.09.): Ruhepuls hoch und HRV tief, dazu Hauttemperatur erhöht, Atemfrequenz erhöht.",
            "days": 3,
            "since": "2026-09-23"
          },
          {
            "kind": "recovery_rot",
            "severity": "warn",
            "text": "Recovery seit 3 Tagen rot (< 34 %).",
            "days": 3,
            "since": "2026-09-23"
          }
        ],
        "recovery": 17,
        "recovery_zone": "red",
        "chips": [
          {
            "key": "rhr",
            "label": "Ruhepuls",
            "value": 60.0,
            "unit": "bpm",
            "delta": 4.0,
            "delta_unit": "bpm",
            "z": 2.67,
            "display": "+4",
            "role": "main",
            "direction": "up",
            "flagged": true,
            "evaluable": true,
            "reason": null
          },
          {
            "key": "hrv",
            "label": "HRV",
            "value": 41.3,
            "unit": "ms",
            "delta": -38,
            "delta_unit": "%",
            "z": -5.56,
            "display": "−38 %",
            "role": "main",
            "direction": "down",
            "flagged": true,
            "evaluable": true,
            "reason": null
          },
          {
            "key": "skin_temp",
            "label": "Haut",
            "value": 34.54,
            "unit": "°C",
            "delta": 0.45,
            "delta_unit": "°C",
            "z": 2.97,
            "display": "+0,4 °C",
            "role": "support",
            "direction": "up",
            "flagged": true,
            "evaluable": true,
            "reason": null
          },
          {
            "key": "resp_rate",
            "label": "Atmung",
            "value": 16.2,
            "unit": "/min",
            "delta": 1.0,
            "delta_unit": "/min",
            "z": 3.33,
            "display": "+1,0",
            "role": "support",
            "direction": "up",
            "flagged": true,
            "evaluable": true,
            "reason": null
          },
          {
            "key": "glucose_night",
            "label": "Glukose Nacht",
            "value": 156.4,
            "unit": "mg/dL",
            "delta": 36.7,
            "delta_unit": "mg/dL",
            "z": 4.54,
            "display": "+37",
            "role": "context",
            "direction": "up",
            "flagged": true,
            "evaluable": true,
            "reason": null
          },
          {
            "key": "tdd",
            "label": "Tagesinsulin",
            "value": 51.8,
            "unit": "U",
            "delta": 22,
            "delta_unit": "%",
            "z": 2.64,
            "display": "+22 %",
            "role": "context",
            "direction": "up",
            "flagged": true,
            "evaluable": true,
            "reason": null
          }
        ],
        "resist_up": true,
        "context_text": "Dazu Glukose/Insulinbedarf erhöht.",
        "glucose_signal": {
          "evaluable": true,
          "reason": null,
          "night_date": "2026-09-25",
          "day_date": "2026-09-24",
          "night_mean": 156.4,
          "day_mean": 176.3,
          "tar": 33.7,
          "night_coverage": 100,
          "day_coverage": 100,
          "night_delta": 36.7,
          "day_delta": 35.7,
          "tar_delta": 18.8,
          "z_night": 4.54,
          "z_day": 4.38,
          "z_tar": 3.64,
          "glu_up": true,
          "signals": [
            "night_mean",
            "day_mean",
            "tar"
          ]
        },
        "insulin_signal": {
          "evaluable": true,
          "reason": null,
          "date": "2026-09-24",
          "tdd": 51.8,
          "tdd_baseline": 42.5,
          "tdd_delta_pct": 22,
          "per_10g_carbs": 2.4,
          "per_10g_baseline": 2.22,
          "p10_delta_pct": 8,
          "z_tdd": 2.64,
          "z_p10": 0.88,
          "ins_auto": 2.7,
          "carbs": 216,
          "basal_source": "reconstructed",
          "ins_up": true,
          "signals": [
            "tdd"
          ]
        },
        "baseline": {
          "days": 28,
          "n": 28,
          "rhr": 56,
          "hrv": 66,
          "skin_temp": 34.1,
          "resp_rate": 15.2
        },
        "days": [
          {
            "date": "2026-09-19",
            "rhr": 57,
            "hrv": 64,
            "recovery": 48,
            "sleep_h": 7.3,
            "flagged": false
          },
          {
            "date": "2026-09-20",
            "rhr": 53,
            "hrv": 70,
            "recovery": 63,
            "sleep_h": 7.5,
            "flagged": false
          },
          {
            "date": "2026-09-21",
            "rhr": 54,
            "hrv": 75,
            "recovery": 67,
            "sleep_h": 7.7,
            "flagged": false
          },
          {
            "date": "2026-09-22",
            "rhr": 56,
            "hrv": 64,
            "recovery": 60,
            "sleep_h": 7.2,
            "flagged": false
          },
          {
            "date": "2026-09-23",
            "rhr": 64,
            "hrv": 44,
            "recovery": 21,
            "sleep_h": 7.4,
            "flagged": true
          },
          {
            "date": "2026-09-24",
            "rhr": 63,
            "hrv": 59,
            "recovery": 24,
            "sleep_h": 6.3,
            "flagged": true
          },
          {
            "date": "2026-09-25",
            "rhr": 60,
            "hrv": 41,
            "recovery": 17,
            "sleep_h": 6.9,
            "flagged": true
          }
        ]
      },
      "outlook": {
        "status": "warn",
        "lines": [
          "COVID in Wien auf hohem Niveau (78% eines typischen Höhepunkts).",
          "COVID in Deutschland auf hohem Niveau (60% eines typischen Höhepunkts)."
        ],
        "alerts": [
          {
            "severity": "warn",
            "text": "COVID in Wien auf hohem Niveau (78% eines typischen Höhepunkts)."
          },
          {
            "severity": "warn",
            "text": "COVID in Deutschland auf hohem Niveau (60% eines typischen Höhepunkts)."
          }
        ],
        "generated_at": "2026-09-25T06:40:00+02:00"
      },
      "tiles": {
        "viruses_wien": {
          "source": "abwasser_wien",
          "region": "Wien",
          "unit": "gc/day",
          "latest_date": "2026-09-20",
          "stale": false,
          "evaluable": true,
          "reason": null,
          "viruses": [
            {
              "virus": "COVID",
              "metric": "ww_sars_cov2",
              "latest_date": "2026-09-20",
              "latest": 76333535446425.0,
              "stale": false,
              "trend": "stabil",
              "trend_fine": "leicht steigend",
              "trend_rank": 1,
              "trend_ratio": 1.24,
              "level": "sehr hoch",
              "level_rank": 4,
              "pct_of_typical_peak": 78.3,
              "vs_usual_this_week": 1.59,
              "typical_onset_kw": null,
              "typical_onset_date": null,
              "weeks_until_typical_onset": null
            },
            {
              "virus": "Grippe",
              "metric": "ww_influenza",
              "latest_date": "2026-09-20",
              "latest": 96246335026.0,
              "stale": false,
              "trend": "stabil",
              "trend_fine": "gleich",
              "trend_rank": 0,
              "trend_ratio": 1.01,
              "level": "sehr niedrig",
              "level_rank": 0,
              "pct_of_typical_peak": 4.7,
              "vs_usual_this_week": 1.02,
              "typical_onset_kw": 51,
              "typical_onset_date": "2026-12-20",
              "weeks_until_typical_onset": 12
            },
            {
              "virus": "RSV",
              "metric": "ww_rsv",
              "latest_date": "2026-09-20",
              "latest": 124410224074.0,
              "stale": false,
              "trend": "stabil",
              "trend_fine": "gleich",
              "trend_rank": 0,
              "trend_ratio": 0.94,
              "level": "sehr niedrig",
              "level_rank": 0,
              "pct_of_typical_peak": 4.0,
              "vs_usual_this_week": 1.03,
              "typical_onset_kw": 45,
              "typical_onset_date": "2026-11-08",
              "weeks_until_typical_onset": 6
            }
          ]
        },
        "pollen": {
          "place": "Wien",
          "evaluable": true,
          "reason": null,
          "generated_at": "2026-09-25T06:40:00+02:00",
          "allergens": [
            {
              "allergen": "birch",
              "name": "Birke",
              "thresholds": {
                "mittel": 15,
                "hoch": 90
              },
              "season": {
                "start": "03-20",
                "end": "05-10"
              },
              "in_season": false,
              "forecast": [
                {
                  "date": "2026-09-25",
                  "mean": 0.0,
                  "max": 1.0,
                  "level": "keine",
                  "level_rank": 0
                },
                {
                  "date": "2026-09-26",
                  "mean": 0.0,
                  "max": 1.0,
                  "level": "keine",
                  "level_rank": 0
                },
                {
                  "date": "2026-09-27",
                  "mean": 0.0,
                  "max": 1.0,
                  "level": "keine",
                  "level_rank": 0
                },
                {
                  "date": "2026-09-28",
                  "mean": 0.0,
                  "max": 1.0,
                  "level": "keine",
                  "level_rank": 0
                }
              ],
              "max_level": "keine",
              "max_level_rank": 0
            },
            {
              "allergen": "grass",
              "name": "Gräser",
              "thresholds": {
                "mittel": 10,
                "hoch": 50
              },
              "season": {
                "start": "05-01",
                "end": "07-31"
              },
              "in_season": false,
              "forecast": [
                {
                  "date": "2026-09-25",
                  "mean": 3.0,
                  "max": 4.0,
                  "level": "niedrig",
                  "level_rank": 1
                },
                {
                  "date": "2026-09-26",
                  "mean": 3.0,
                  "max": 4.0,
                  "level": "niedrig",
                  "level_rank": 1
                },
                {
                  "date": "2026-09-27",
                  "mean": 13.0,
                  "max": 14.0,
                  "level": "mittel",
                  "level_rank": 2
                },
                {
                  "date": "2026-09-28",
                  "mean": 3.0,
                  "max": 4.0,
                  "level": "niedrig",
                  "level_rank": 1
                }
              ],
              "max_level": "mittel",
              "max_level_rank": 2
            }
          ],
          "allergy": {
            "active": false,
            "place": "Wien",
            "allergens": [],
            "reasons": []
          }
        },
        "glucose": {
          "evaluable": true,
          "reason": null,
          "last_ts": "2026-09-25T13:15:20+02:00",
          "last_value": 240,
          "age_min": 14,
          "coverage_24h": 99,
          "tir_24h": 66,
          "tbr_24h": 0,
          "tar_24h": 34,
          "mean_24h": 177,
          "cv_24h": 17,
          "gmi_24h": 7.5,
          "night_mean": 156,
          "spark_24h": [
            202,
            174,
            157,
            144,
            158,
            221,
            198,
            178,
            158,
            156,
            153,
            157,
            155,
            157,
            158,
            158,
            165,
            180,
            243,
            221,
            192,
            166,
            171,
            234
          ],
          "spark_start": "2026-09-24T14:00:00+02:00",
          "target": [
            70,
            180
          ],
          "up": true,
          "sources": [
            "dexcom_share",
            "loop"
          ]
        },
        "recovery": {
          "date": "2026-09-25",
          "evaluable": true,
          "reason": null,
          "recovery": 17,
          "zone": "red",
          "sleep_h": 6.9,
          "hrv": 41,
          "rhr": 60,
          "resp_rate": 16.2,
          "skin_temp": 34.5,
          "strain": 4.8
        },
        "insulin": {
          "date": "2026-09-24",
          "evaluable": true,
          "reason": null,
          "tdd": 51.8,
          "tdd_baseline": 42.5,
          "tdd_delta_pct": 22,
          "per_10g_carbs": 2.4,
          "per_10g_baseline": 2.22,
          "per_10g_delta_pct": 8,
          "ins_auto": 2.7,
          "bolus": 30.8,
          "basal": 21.0,
          "carbs_g": 216,
          "tdd_last7": [
            42.4,
            40.2,
            43.7,
            39.4,
            42.0,
            41.0,
            51.8
          ],
          "tdd_last7_start": "2026-09-18",
          "basal_source": "reconstructed",
          "up": true
        },
        "loop": {
          "evaluable": true,
          "reason": null,
          "last_ts": "2026-09-25T13:15:20+02:00",
          "age_min": 14,
          "last_cgm_ts": "2026-09-25T13:15:20+02:00",
          "last_glucose": 240,
          "cgm_age_min": 14,
          "cgm_stale": false,
          "iob": 1.25,
          "iob_ts": "2026-09-25T13:15:00+02:00",
          "cob": 5,
          "temp_basal_rate": 0.8,
          "temp_basal_ts": "2026-09-25T13:10:00+02:00",
          "temp_basal_duration_min": 30,
          "temp_basal_active": true,
          "last_sensor_change": "2026-09-22T08:30:00+02:00"
        }
      },
      "environment": {
        "season": "2026/27",
        "viruses": {
          "abwasser_wien": {
            "source": "abwasser_wien",
            "region": "Wien",
            "unit": "gc/day",
            "latest_date": "2026-09-20",
            "stale": false,
            "evaluable": true,
            "reason": null,
            "viruses": [
              {
                "virus": "COVID",
                "metric": "ww_sars_cov2",
                "latest_date": "2026-09-20",
                "latest": 76333535446425.0,
                "stale": false,
                "trend": "stabil",
                "trend_fine": "leicht steigend",
                "trend_rank": 1,
                "trend_ratio": 1.24,
                "level": "sehr hoch",
                "level_rank": 4,
                "pct_of_typical_peak": 78.3,
                "vs_usual_this_week": 1.59,
                "typical_onset_kw": null,
                "typical_onset_date": null,
                "weeks_until_typical_onset": null
              },
              {
                "virus": "Grippe",
                "metric": "ww_influenza",
                "latest_date": "2026-09-20",
                "latest": 96246335026.0,
                "stale": false,
                "trend": "stabil",
                "trend_fine": "gleich",
                "trend_rank": 0,
                "trend_ratio": 1.01,
                "level": "sehr niedrig",
                "level_rank": 0,
                "pct_of_typical_peak": 4.7,
                "vs_usual_this_week": 1.02,
                "typical_onset_kw": 51,
                "typical_onset_date": "2026-12-20",
                "weeks_until_typical_onset": 12
              },
              {
                "virus": "RSV",
                "metric": "ww_rsv",
                "latest_date": "2026-09-20",
                "latest": 124410224074.0,
                "stale": false,
                "trend": "stabil",
                "trend_fine": "gleich",
                "trend_rank": 0,
                "trend_ratio": 0.94,
                "level": "sehr niedrig",
                "level_rank": 0,
                "pct_of_typical_peak": 4.0,
                "vs_usual_this_week": 1.03,
                "typical_onset_kw": 45,
                "typical_onset_date": "2026-11-08",
                "weeks_until_typical_onset": 6
              }
            ]
          },
          "abwasser_de": {
            "source": "abwasser_de",
            "region": "Deutschland",
            "unit": "gc/L",
            "latest_date": "2026-09-20",
            "stale": false,
            "evaluable": true,
            "reason": null,
            "viruses": [
              {
                "virus": "COVID",
                "metric": "ww_sars_cov2",
                "latest_date": "2026-09-20",
                "latest": 65635.0,
                "stale": false,
                "trend": "stabil",
                "trend_fine": "gleich",
                "trend_rank": 0,
                "trend_ratio": 1.03,
                "level": "hoch",
                "level_rank": 3,
                "pct_of_typical_peak": 60.0,
                "vs_usual_this_week": 1.35,
                "typical_onset_kw": null,
                "typical_onset_date": null,
                "weeks_until_typical_onset": null
              },
              {
                "virus": "Grippe",
                "metric": "ww_influenza",
                "latest_date": "2026-09-20",
                "latest": 98.0,
                "stale": false,
                "trend": "stabil",
                "trend_fine": "gleich",
                "trend_rank": 0,
                "trend_ratio": 1.03,
                "level": "sehr niedrig",
                "level_rank": 0,
                "pct_of_typical_peak": 4.4,
                "vs_usual_this_week": 1.03,
                "typical_onset_kw": 50,
                "typical_onset_date": "2026-12-13",
                "weeks_until_typical_onset": 11
              },
              {
                "virus": "RSV",
                "metric": "ww_rsv",
                "latest_date": "2026-09-20",
                "latest": 128.0,
                "stale": false,
                "trend": "stabil",
                "trend_fine": "gleich",
                "trend_rank": 0,
                "trend_ratio": 0.97,
                "level": "sehr niedrig",
                "level_rank": 0,
                "pct_of_typical_peak": 3.9,
                "vs_usual_this_week": 1.06,
                "typical_onset_kw": 45,
                "typical_onset_date": "2026-11-08",
                "weeks_until_typical_onset": 6
              }
            ]
          }
        },
        "pollen": [
          {
            "place": "Wien",
            "evaluable": true,
            "reason": null,
            "generated_at": "2026-09-25T06:40:00+02:00",
            "allergens": [
              {
                "allergen": "birch",
                "name": "Birke",
                "thresholds": {
                  "mittel": 15,
                  "hoch": 90
                },
                "season": {
                  "start": "03-20",
                  "end": "05-10"
                },
                "in_season": false,
                "forecast": [
                  {
                    "date": "2026-09-25",
                    "mean": 0.0,
                    "max": 1.0,
                    "level": "keine",
                    "level_rank": 0
                  },
                  {
                    "date": "2026-09-26",
                    "mean": 0.0,
                    "max": 1.0,
                    "level": "keine",
                    "level_rank": 0
                  },
                  {
                    "date": "2026-09-27",
                    "mean": 0.0,
                    "max": 1.0,
                    "level": "keine",
                    "level_rank": 0
                  },
                  {
                    "date": "2026-09-28",
                    "mean": 0.0,
                    "max": 1.0,
                    "level": "keine",
                    "level_rank": 0
                  }
                ],
                "max_level": "keine",
                "max_level_rank": 0
              },
              {
                "allergen": "grass",
                "name": "Gräser",
                "thresholds": {
                  "mittel": 10,
                  "hoch": 50
                },
                "season": {
                  "start": "05-01",
                  "end": "07-31"
                },
                "in_season": false,
                "forecast": [
                  {
                    "date": "2026-09-25",
                    "mean": 3.0,
                    "max": 4.0,
                    "level": "niedrig",
                    "level_rank": 1
                  },
                  {
                    "date": "2026-09-26",
                    "mean": 3.0,
                    "max": 4.0,
                    "level": "niedrig",
                    "level_rank": 1
                  },
                  {
                    "date": "2026-09-27",
                    "mean": 13.0,
                    "max": 14.0,
                    "level": "mittel",
                    "level_rank": 2
                  },
                  {
                    "date": "2026-09-28",
                    "mean": 3.0,
                    "max": 4.0,
                    "level": "niedrig",
                    "level_rank": 1
                  }
                ],
                "max_level": "mittel",
                "max_level_rank": 2
              }
            ]
          }
        ],
        "allergy": {
          "active": false,
          "place": "Wien",
          "allergens": [],
          "reasons": []
        },
        "hints": [
          {
            "kind": "flu_vaccine",
            "severity": "info",
            "text": "Grippeimpfung ab 01.10. einplanen.",
            "icon": "syringe"
          }
        ]
      },
      "push": {
        "last": {
          "title": "Whoop-Check: Infektmuster seit 3 Tagen (ab 23.09.)",
          "body": null,
          "sent_at": "2026-09-25T12:30:00+02:00",
          "thread_id": "whoop",
          "tab": "heute",
          "channels": [
            "ntfy",
            "apns"
          ]
        },
        "devices": 1,
        "test_push_available": false
      },
      "errors": []
    }
    """#
}
