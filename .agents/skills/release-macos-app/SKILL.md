---
name: release-macos-app
description: >-
  Use this skill when the user asks to release a new version of the macOS app (e.g. "release version 0.1.3", "create a new release", "publish the next version"). This skill completely automates version bumping, building, packaging, creating the GitHub release, and updating the Sparkle appcast.
---

# Release macOS App

This skill automates the release process for the WhizMe macOS app. When you are instructed to release a new version, follow these steps exactly:

## Step 1: Determine the Target Version
Identify the target version (e.g. `0.1.3`). If the user does not specify one, check the current `MARKETING_VERSION` in `Scripts/build.sh` and ask the user which version they want to bump it to.

## Step 2: Extract Current Build Version
Use `grep_search` to find `BUILD_VERSION` in `Scripts/build.sh`. Increment this integer by 1 (e.g., if it is `"3"`, the new build version is `"4"`). This is strictly necessary to avoid Sparkle caching conflicts.

## Step 3: Bump Versions
Use your code editing tools (`replace_file_content` or `multi_replace_file_content`) to update the following:
1.  **`Scripts/build.sh`**: 
    - Update `MARKETING_VERSION="<current>"` to `MARKETING_VERSION="<new_version>"`
    - Update `BUILD_VERSION="<current_build>"` to `BUILD_VERSION="<new_build>"`
2.  **`WhizMe.xcodeproj/project.pbxproj`**: 
    - Update all occurrences of `MARKETING_VERSION = <current>;` to `MARKETING_VERSION = <new_version>;`
    - Update all occurrences of `CURRENT_PROJECT_VERSION = <current_build>;` to `CURRENT_PROJECT_VERSION = <new_build>;`

## Step 4: Commit the Version Bump
Run the following command to commit and push the version updates:
```bash
git commit -am "Bump version to <new_version>" && git push
```

## Step 5: Build and Package the Release
Execute the release script (passing the new version) and wait for it to complete. This step may take a minute or two:
```bash
./Scripts/release.sh <new_version>
```
*Note: Wait for the background task to complete successfully. The script will generate the `.dmg` and `.delta` artifacts in the `dist/` folder.*

## Step 6: Create the GitHub Release
The GitHub CLI must be authenticated. Execute the following to create the release and upload the artifacts from `dist/`:
```bash
gh release create v<new_version> dist/WhizMe-v<new_version>.dmg dist/*.delta --title "Release v<new_version>" --generate-notes
```

## Step 7: Push the Updated Appcast
After the release artifacts are successfully uploaded to GitHub, commit and push the `appcast.xml` (which was updated by `release.sh`) to the root of the repository:
```bash
git add appcast.xml && git commit -m "Release v<new_version>" && git push
```
*Warning: This step MUST be done after Step 6, otherwise clients will hit a 404 when downloading the update.*

## Step 8: Walkthrough
Once finished, provide a brief summary to the user indicating the release was published successfully.
