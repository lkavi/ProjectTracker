# Publishing guide — App Store and Mac App Store

A step-by-step path from this repository to a live listing. Everything marked ✅ is already done in the code; everything marked ☐ is a click or a decision in Xcode, App Store Connect or the Developer portal.

## 0. What is already in place

- ✅ Bundle identifiers: `com.lkavi.ProjectTracker` (app, shared by iOS and macOS) and `com.lkavi.ProjectTracker.Widget`.
- ✅ Deployment targets iOS 17.0 / macOS 14.0, iPhone + iPad device families, native Mac (not Catalyst).
- ✅ Privacy manifests (`PrivacyInfo.xcprivacy`) in the app and the widget.
- ✅ Export compliance answered in `Info.plist` (`ITSAppUsesNonExemptEncryption = NO`), so no encryption questionnaire at upload.
- ✅ Mac App Sandbox and user-selected file access enabled through build settings.
- ✅ App category (`public.app-category.productivity`), launch screen, iOS 1024 px and full macOS icon set.
- ✅ Version 1.0, build 1, identical in the app and the widget (App Store requires the extension to match).
- ✅ Privacy policy published at https://github.com/lkavi/ProjectTracker/blob/main/PRIVACY.md.
- ✅ Store copy and screenshots in [`listing.md`](listing.md) and [`screenshots/`](screenshots/).

## 1. Prerequisites (once)

- ☐ An active **Apple Developer Program** membership for the team whose ID is in your `Config/Local.xcconfig`.
- ☐ In App Store Connect → *Business* (Agreements, Tax, and Banking), the **Free Apps** agreement accepted. Paid-apps banking details are not needed for a free app.
- ☐ Xcode 26 or later, signed in with the same Apple Account (Xcode → Settings → Accounts). Archive and upload with a **release** Xcode: App Store Connect rejects builds made with beta versions (on this Mac that means `/Applications/Xcode.app`, not `Xcode-beta.app`).
- ☐ A real iPhone and the Mac itself for testing. The simulator cannot sign in to iCloud, so sync, the widget picker and notifications must be checked on hardware.

## 2. Identifiers and capabilities (automatic, but verify)

1. ☐ Open `ProjectTracker.xcodeproj`, select the **ProjectTracker** target → *Signing & Capabilities*. With *Automatically manage signing* on and your team resolved from `Config/Local.xcconfig`, Xcode registers the App ID, the iCloud container `iCloud.lkavi.fyppipeline` and the App Group `group.lkavi.fyppipeline`, and creates the provisioning profiles.
2. ☐ Repeat for the **ProjectTrackerWidgetExtension** target (App Groups only).
3. ☐ Confirm at https://developer.apple.com/account → *Identifiers*: the app's App ID has **iCloud** (CloudKit off, iCloud Documents on, container assigned) and **App Groups**; the widget's App ID has **App Groups**. Both must be enabled for **iOS** and **macOS** platforms.
4. Troubleshooting: if signing complains about `com.apple.developer.icloud-extended-share-access`, delete that key from `ProjectTracker/ProjectTracker.entitlements`; it is optional.

## 3. Test on devices before you archive

- ☐ Run on your iPhone and on the Mac from Xcode. Create a project, tick tasks, attach a PDF, add a library item, then check the other device picks everything up through iCloud.
- ☐ Add the widget (all three sizes), long-press → *Edit Widget* and pick a project.
- ☐ Turn on a daily reminder in Settings and check the permission prompt and the delivered notification.
- ☐ Export a project, import it back, and import a deliberately broken file to see the error alert.
- ☐ Delete the app and reinstall to check the empty state and first-run flow.

## 4. Create the App Store Connect record

1. ☐ https://appstoreconnect.apple.com → *My Apps* → **+** → *New App*.
2. ☐ Platforms: tick **iOS** and **macOS** (one record, one bundle ID, universal purchase).
3. ☐ Name: use the recommended store name from `listing.md` (`Project Tracker: Uni & Thesis`). If App Store Connect says the name is taken, use one of the fallbacks listed there.
4. ☐ Primary language: English (U.K.) or English (U.S.), to match the copy you paste.
5. ☐ Bundle ID: pick `com.lkavi.ProjectTracker` from the list. SKU: any unique string, e.g. `PROJECTTRACKER-001`. User access: Full Access.

## 5. Archive and upload

Do this twice, once per platform, from the same commit.

**iOS**
1. ☐ Xcode → *Product* → *Destination* → **Any iOS Device (arm64)**.
2. ☐ *Product* → **Archive**. When the Organizer opens, select the archive → **Validate App** (fix anything it reports) → **Distribute App** → *App Store Connect* → *Upload*. Keep *Upload your app's symbols* on and *Manage Version and Build Number* off (you control the build number in the project).

**macOS**
3. ☐ *Product* → *Destination* → **Any Mac (Apple Silicon, Intel)** → *Archive* → *Validate* → *Distribute App* → *App Store Connect* → *Upload*. Choose the Mac App Store distribution when asked (this signs with the sandbox entitlements).

Command-line equivalent, if you prefer scripts:

```bash
xcodebuild -project ProjectTracker.xcodeproj -scheme ProjectTracker \
  -destination 'generic/platform=iOS' archive -archivePath build/iOS.xcarchive
xcodebuild -project ProjectTracker.xcodeproj -scheme ProjectTracker \
  -destination 'generic/platform=macOS' archive -archivePath build/macOS.xcarchive
```

Then open each `.xcarchive` in the Organizer (double-click) to validate and upload, or export and upload from the command line with an options plist (`method` = `app-store-connect`, `signingStyle` = `automatic`, `teamID` = your team, `destination` = `export` to produce the `.ipa`/`.pkg` or `upload` to send it straight to App Store Connect):

```bash
xcodebuild -exportArchive -archivePath build/iOS.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export-ios -allowProvisioningUpdates
```

`destination = upload` only works once the app record exists in App Store Connect.

4. ☐ Wait for the "has completed processing" email for each build (usually 5–30 minutes).
5. For every later upload, bump `CURRENT_PROJECT_VERSION` in **both** the app and the widget target (or `MARKETING_VERSION` for a new version). Uploads with a reused build number are rejected.

## 6. TestFlight (recommended, a few days)

- ☐ App Store Connect → *TestFlight* → add yourself (and a friend or two) as **Internal Testers** under App Store Connect Users. Internal testing needs no review.
- ☐ Install through the TestFlight app on iPhone and on the Mac, and use it with your real project for a few days. This is the cheapest place to catch sync and notification issues.

## 7. Fill in the version metadata

Open the **1.0 Prepare for Submission** page for each platform and paste from `listing.md`:

- ☐ **Screenshots**: iPhone 6.9" set, iPad 13" set, Mac set (exact sizes are already correct). App Store Connect scales them to smaller devices.
- ☐ **Promotional Text**, **Description**, **Keywords**, **Support URL**, **Marketing URL**.
- ☐ **Version** 1.0, **Copyright** `© 2026 <your name>`.
- ☐ **Build**: select the processed build.
- ☐ **App Review Information**: your name, phone number and email (kept private by Apple); *Sign-in required*: No; paste the *Notes for App Review* from `listing.md`.
- ☐ **Version Release**: *Manually release this version* is the safest for a first release.

Then, on the app-level pages:

- ☐ **App Information**: Subtitle, Primary category Productivity, Secondary Education, Content Rights: does not contain third-party content, Age Rating questionnaire → 4+.
- ☐ **Pricing and Availability**: Free, all territories (or your choice).
- ☐ **App Privacy**: *Data Not Collected* → **Publish**. Add the privacy policy URL here as well.

## 8. Submit for review

- ☐ *Add for Review* → *Submit to App Review* for iOS and for macOS. First reviews typically take 24–48 hours.
- If a reviewer asks about the AI-tailoring step, point to the review notes: it is optional, happens outside the app, and the app is complete without it.
- Common first-submission pitfalls, already addressed here: missing privacy manifest (added), export compliance (in the plist), placeholder icon or launch screen (none), extension version mismatch (identical), unsandboxed Mac build (sandbox on).

## 9. After approval

- ☐ Release the version (if you chose manual release), then check the live listing on both stores.
- ☐ Keep the privacy policy URL working; Apple checks it on every submission.
- Plan a 1.0.1 from what real users report; the README's *Current limitations* lists the known gaps.

## Checklist of decisions only you can make

- ☐ Final store name (uniqueness is checked live when you create the record).
- ☐ A licence for the public repository (MIT is the usual choice for a small open-source app). Without one, the code is "all rights reserved" by default.
- ☐ Whether to host the privacy policy on a site of your own instead of GitHub (GitHub is acceptable to Apple).
