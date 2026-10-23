#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cargo test --offline -j 2
bash scripts/build.sh
mkdir -p build/validation
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'color=red:s=320x240:r=30:d=1' -f lavfi -i 'color=green:s=320x240:r=30:d=1' -f lavfi -i 'color=blue:s=320x240:r=30:d=1' -f lavfi -i 'color=white:s=320x240:r=30:d=1' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=4' -filter_complex '[0:v][1:v][2:v][3:v]concat=n=4:v=1:a=0[video]' -map '[video]' -map 4:a -c:v libx264 -pix_fmt yuv420p -c:a aac build/validation/input.mp4
build/validate "$PWD/build/validation/input.mp4" "$PWD/build/validation/output.mp4" "$PWD/build/validation/project.json"
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,duration -show_entries format=duration -of json build/validation/output.mp4
ffmpeg -hide_banner -loglevel error -i build/validation/output.mp4 -vf 'select=eq(n\,0)+eq(n\,59),scale=1:1' -fps_mode passthrough -f rawvideo -pix_fmt rgb24 build/validation/endpoints.rgb -y
node -e 'const bytes=require("fs").readFileSync("build/validation/endpoints.rgb"); if(bytes.length!==6 || !(bytes[1]>bytes[0]+50 && bytes[1]>bytes[2]+50 && bytes[5]>bytes[3]+100 && bytes[5]>bytes[4]+100)) throw Error("Wrong trim endpoints: "+[...bytes]); console.log("PASS: first frame green, last frame blue", [...bytes]);'
