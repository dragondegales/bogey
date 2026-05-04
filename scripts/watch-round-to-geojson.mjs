#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import path from "node:path";

const inputPath = process.argv[2];
const outputPath = process.argv[3] ?? "buddygolf-round.geojson";

if (!inputPath) {
  console.error("Usage: node scripts/watch-round-to-geojson.mjs <watch-container-or-BuddyGolf-dir> [output.geojson]");
  process.exit(1);
}

function findFile(root, filename) {
  const entries = readdirSync(root, { withFileTypes: true });

  for (const entry of entries) {
    const entryPath = path.join(root, entry.name);
    if (entry.isFile() && entry.name === filename) {
      return entryPath;
    }

    if (entry.isDirectory()) {
      const found = findFile(entryPath, filename);
      if (found) {
        return found;
      }
    }
  }

  return null;
}

function readJSON(filePath) {
  return JSON.parse(readFileSync(filePath, "utf8"));
}

const resolvedInput = path.resolve(inputPath);
const inputStat = statSync(resolvedInput);
const root = inputStat.isDirectory() ? resolvedInput : path.dirname(resolvedInput);
const roundStatePath = inputStat.isFile() && path.basename(resolvedInput) === "round-state.json"
  ? resolvedInput
  : findFile(root, "round-state.json");
const coursesCachePath = findFile(root, "courses-cache.json");

if (!roundStatePath) {
  console.error(`Could not find round-state.json under ${resolvedInput}`);
  process.exit(1);
}

const roundState = readJSON(roundStatePath);
const courses = coursesCachePath && existsSync(coursesCachePath) ? readJSON(coursesCachePath) : [];
const selectedCourse = courses.find((course) => course.id === roundState.selectedCourseID)
  ?? courses.find((course) => course.id === roundState.round?.courseID);
const round = roundState.round;

if (!round) {
  console.error(`No round object found in ${roundStatePath}`);
  process.exit(1);
}

const features = [];

if (selectedCourse?.holes) {
  for (const hole of selectedCourse.holes) {
    features.push({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [hole.greenLongitude, hole.greenLatitude],
      },
      properties: {
        course_id: selectedCourse.id,
        hole_number: hole.holeNumber,
        layer: "green_center",
        name: `Hole ${hole.holeNumber} green center`,
        order: hole.holeNumber,
        par: hole.par,
        stroke_index: hole.strokeIndex ?? null,
      },
    });
  }
}

for (const holeState of round.holeStates ?? []) {
  for (const shot of holeState.myShotPoints ?? []) {
    features.push({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [shot.longitude, shot.latitude],
      },
      properties: {
        course_id: round.courseID,
        hole_number: shot.holeNumber,
        layer: "shot_point",
        name: `Hole ${shot.holeNumber} shot ${shot.strokeNumber}`,
        order: shot.strokeNumber,
        stroke_number: shot.strokeNumber,
        timestamp: shot.timestamp,
      },
    });
  }
}

const geoJSON = {
  type: "FeatureCollection",
  properties: {
    source: "BuddyGolf Watch App",
    round_id: round.id,
    course_id: round.courseID,
    selected_course_id: roundState.selectedCourseID,
    current_hole_number: round.currentHoleNumber,
    generated_at: new Date().toISOString(),
    round_state_file: roundStatePath,
    courses_cache_file: coursesCachePath,
  },
  features,
};

const resolvedOutput = path.resolve(outputPath);
mkdirSync(path.dirname(resolvedOutput), { recursive: true });
writeFileSync(resolvedOutput, `${JSON.stringify(geoJSON, null, 2)}\n`);
console.log(`Wrote ${features.length} features to ${resolvedOutput}`);
