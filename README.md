# OnePic 📸

> **把时间变成可以收藏的视频。**  
> Turn time into a video you can keep.

OnePic is an iOS app for intentional daily photo journaling — built around one idea: **shoot one photo a day, watch yourself change over time.**

---

## What It Does

Every day, open OnePic, take one photo. That's it.

Over days and weeks, your photos become a time-lapse of your life — your face, your plants, your fitness journey, anything you choose to document. The app turns that collection into a video you can share.

---

## Core Features

### 📷 Daily Capture with Ghost Overlay
When you open the camera, the previous day's photo appears as a semi-transparent ghost behind the live viewfinder. Align yourself to the ghost, shoot — every photo lines up perfectly.

### 🎞 Film Strip Timeline
Your photos arrange into a vertical film strip. Drag the timeline and watch your photos flip like a physical reel — the main photo animates as you scroll, giving you a real sense of time passing.

### 🔥 Streak System
Miss a day, lose your streak. The app tracks consecutive days per project, with milestone achievements at 7, 30, 100, and 365 days.

### 🎬 One-Tap Video Export
Select a date range, tap Export — the app stitches your photos into an MP4 with your choice of speed and watermark. Ready to share to TikTok, Instagram Reels, or 小红书.

### 🗂 Multiple Projects
Track your face. Track your plants. Track your fitness. Each project has its own independent timeline, streak, and reminder.

### ⏰ Daily Reminders
Set a reminder time per project. The app sends a gentle nudge if you haven't shot that day.

---

## Design

OnePic is built around a **glass morphism + physical interaction** design language:

- All UI elements float as glass cards over the live camera feed
- The shutter button has a 3-layer structure with a physical press-and-rebound animation
- Timeline scrubbing uses custom physics with damping and inertia — like physically flicking a film reel
- Haptic feedback at every meaningful interaction: selection, impact, and confirmation

---

## Tech Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9 |
| UI Framework | SwiftUI |
| Data | SwiftData |
| Camera | AVFoundation |
| Photo Storage | PhotoKit |
| Face Detection | Vision Framework |
| Video Export | AVAssetWriter |
| Notifications | UserNotifications |
| Platform | iOS 17+ |

---

## Project Structure

```
OnePic/
├── OnePicApp.swift          # App entry point
├── ContentView.swift        # Root view
├── Project.swift            # Project data model
├── Photo.swift              # Photo data model
├── ProjectListView.swift    # Home screen — project grid
├── ProjectDetailView.swift  # Timeline + film strip interaction
├── CameraCaptureView.swift  # Camera with ghost overlay
├── CameraController.swift   # AVFoundation camera logic
├── CameraPreviewView.swift  # Live camera preview layer
├── GhostSettingsView.swift  # Ghost opacity controls
├── ImageWatermark.swift     # Date/day watermark baking
├── PhotoStore.swift         # Photo file management
├── ProjectPickerView.swift  # Project switcher
└── VIP.swift                # Free vs VIP feature gates
```

---

## Status

Currently in development. Targeting App Store submission — May 2026.

- [x] Camera with ghost overlay
- [x] Film strip timeline with physics scrubbing
- [x] Streak system
- [x] Multiple projects
- [x] Date watermark
- [x] Video export
- [ ] iCloud sync
- [ ] In-app purchase (VIP)
- [ ] App Store submission

---

## About

Built by [@dream114514ooo-dev](https://github.com/dream114514ooo-dev)  
Started May 2026 · Bangkok, Thailand

---

*"Every day, one frame. Every year, a film."*
