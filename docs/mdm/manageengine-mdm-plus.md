# Blindspot with ManageEngine Mobile Device Manager Plus

Checked on 2026-10-28 against ManageEngine's documentation, linked below.

Fleet mode needs an MDM that runs a script as root on each Mac. Mobile Device Manager Plus manages
Macs with configuration profiles and apps, and its documentation describes no way to run a script
on a Mac. ManageEngine lists script deployment for Macs under Endpoint Central, its product with an
agent on each Mac
([Mobile Device Manager Plus FAQ](https://www.manageengine.com/mobile-device-management/faq.html),
"Can Mac devices be managed with ManageEngine MDM?").

So with Mobile Device Manager Plus alone, you can:

- **Use Endpoint Central for the check.** If your organization has Endpoint Central, or adds it, follow
  [the Endpoint Central page](manageengine-endpoint-central.md).
- **Have each person run Blindspot on their own Mac.** Send them the steps in the
  [README](../../README.md#run-it). Each person sees their own result, with the files each finding is
  about; nothing reaches you unless they share it.

Blindspot does not ship an installer package, so the app deployment in Mobile Device Manager Plus has
nothing to install.
