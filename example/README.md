# agent_gate example

Runs fully offline with a simulated decider (`DemoDecider`) so you can see the
behavioural routing without any API key.

```sh
flutter run
```

Try:

- **Cart → Checkout**: tap *Apply coupon* twice (it fails) then *Checkout* →
  assisted checkout. Go straight to *Checkout* within a few seconds → express.
- **Transfer → Confirmation**: enter an amount > 5000 → the *rule* fires and
  routes to step-up before any AI runs. Or edit the amount many times → the
  simulated AI flags anomalous behaviour → step-up.
- Toggle the consent switch off → only app context is sent; the decider falls
  back to defaults.

Replace `DemoDecider()` in `main.dart` with
`HttpDecider(endpoint: Uri.parse('https://your-api/decide'))` to go live.
