# Fieldline UAV Mission Dashboard

A fully simulated dashboard for demonstrating disease mapping and variable-rate spraying. It does not require a camera, drone, trained model, dataset, GPS, or external API.

## Setup

From the repository root:

```powershell
python -m pip install -r dashboard/requirements_dashboard.txt
python dashboard/app.py
```

Open `http://localhost:5000`. The dashboard uses browser polling once per second and serves all assets locally except the optional font import in the stylesheet.

## Run a Mission

Enter field length, field width, and drone speed, then select **Start mission**. The simulator flies a lawnmower route across a 10 × 10 grid. Cells are revealed as they are scanned. Disease severity is generated with a low-severity bias, and cells above 5% receive a simulated spray event.

The live panels show:

- Field map: disease severity, scanned area, sprayed cells, and drone position.
- Telemetry: position, heading, altitude, speed, and simulated battery.
- Coverage and treatment: area covered, disease percentage, spray volume, and treated plants.
- Spray activity: recent variable-rate events with location, severity, and amount.

## API

- `GET /api/mission/status`
- `GET /api/drone/telemetry`
- `GET /api/field/disease_map`
- `GET /api/spray/log`
- `POST /api/mission/start` with `{ "field_length": 50, "field_width": 30, "drone_speed": 1 }`
- `POST /api/mission/stop`

## Customize

Edit `dashboard/simulation.py` to change grid resolution, detection interval, severity distribution, or battery drain. Spray levels currently mirror Part C: low is 2 ml/sec for 2 seconds, medium is 4 ml/sec for 4 seconds, and high is 6 ml/sec for 6 seconds. Edit `dashboard/static/css/style.css` to change the visual palette.

## Troubleshooting

- `ModuleNotFoundError`: install `dashboard/requirements_dashboard.txt` using the same Python interpreter that starts Flask.
- Port 5000 in use: change the port in the `app.run` call at the bottom of `dashboard/app.py`.
- A mission appears frozen: confirm the browser can reach `/api/mission/status`; the simulator advances when the dashboard polls its endpoints.
- No spray events appear immediately: the route reveals cells progressively, and low-severity cells intentionally do not trigger treatment.
