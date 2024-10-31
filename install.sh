#!/bin/bash

# Update the package list and install necessary packages
echo "Updating package list..."
sudo apt update -y

# Install Node.js and npm
echo "Installing Node.js and npm..."
sudo apt install -y nodejs npm

# Install FFmpeg
echo "Installing FFmpeg..."
sudo apt install -y ffmpeg

# Install yt-dlp (if not already installed)
if ! command -v yt-dlp &> /dev/null
then
    echo "Installing yt-dlp..."
    sudo apt install -y python3 python3-pip
    pip3 install -U yt-dlp
fi

# Create necessary directories
echo "Creating directories..."
mkdir -p /root/youtube-streamer/streams
mkdir -p /root/youtube-streamer/views

# Create a basic server.js file
cat <<EOF > /root/youtube-streamer/server.js
const express = require('express');
const bodyParser = require('body-parser');
const path = require('path');
const fs = require('fs');
const { exec } = require('child_process');

const app = express();
const PORT = 80;
const streamsDir = path.join(__dirname, 'streams');

app.use(bodyParser.urlencoded({ extended: true }));
app.use(express.static('views'));

// Middleware to serve static files in the streams directory
app.use('/streams', express.static(streamsDir));

// Route to render the main page
app.get('/', (req, res) => {
    fs.readdir(streamsDir, (err, streams) => {
        if (err) {
            console.error('Error reading streams directory:', err);
            return res.status(500).send('Error reading streams directory');
        }
        
        // HTML content
        let html = \`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>YouTube Streamer</title>
        </head>
        <body>
            <h1>YouTube Live Stream Manager</h1>
            <form action="/add-stream" method="POST">
                <label for="videoId">YouTube Video ID:</label>
                <input type="text" name="videoId" required>
                <br>
                <label for="streamName">Stream Name:</label>
                <input type="text" name="streamName" required>
                <br>
                <button type="submit">Add Stream</button>
            </form>

            <h2>Current Streams</h2>
            <ul>
        \`;
        
        streams.forEach(stream => {
            html += \`
                <li>
                    <strong>\${stream}</strong>
                    <form action="/remove-stream" method="POST" style="display:inline;">
                        <input type="hidden" name="streamName" value="\${stream}">
                        <button type="submit">Remove</button>
                    </form>
                    <br>
                    <a href="/streams/\${stream}/stream.m3u8">M3U8 Link</a>
                </li>
            \`;
        });

        html += \`
            </ul>
        </body>
        </html>
        \`;

        res.send(html);
    });
});

// Route to add a stream
app.post('/add-stream', (req, res) => {
    const videoId = req.body.videoId;
    const streamName = req.body.streamName;

    const streamDir = path.join(streamsDir, streamName);
    const m3u8File = path.join(streamDir, 'stream.m3u8');

    // Check if the stream directory exists, if not create it
    if (!fs.existsSync(streamDir)) {
        fs.mkdirSync(streamDir, { recursive: true });
    }

    // Construct yt-dlp command to fetch the stream URL using cookies
    const ytDlpCommand = \`yt-dlp --cookies cookies.txt -f "b" -g "https://www.youtube.com/watch?v=\${videoId}"\`;

    exec(ytDlpCommand, (error, stdout, stderr) => {
        if (error) {
            console.error(\`Error fetching stream URL: \${error.message}\`);
            console.error(\`yt-dlp stderr: \${stderr}\`);
            return res.status(500).send('Error fetching stream URL');
        }

        const streamUrl = stdout.trim();
        console.log(\`Stream URL fetched: \${streamUrl}\`);

        // Start FFmpeg to convert the stream to M3U8
        const ffmpegCommand = \`ffmpeg -loglevel verbose -re -i "\${streamUrl}" -c:v copy -c:a copy -f hls -hls_time 10 -hls_list_size 0 -hls_flags delete_segments "\${m3u8File}"\`;

        const ffmpegProcess = exec(ffmpegCommand, (ffmpegError, ffmpegStdout, ffmpegStderr) => {
            if (ffmpegError) {
                console.error(\`FFmpeg error: \${ffmpegError.message}\`);
                console.error(\`FFmpeg stderr: \${ffmpegStderr}\`);
                return res.status(500).send('Error starting FFmpeg process');
            }

            // Check if the M3U8 file was created
            if (!fs.existsSync(m3u8File)) {
                console.error(\`M3U8 file not created: \${m3u8File}\`);
                return res.status(500).send('M3U8 file not created');
            }

            console.log(\`Stream successfully created at: \${m3u8File}\`);
            return res.redirect('/');
        });

        ffmpegProcess.stderr.on('data', (data) => {
            console.error(\`FFmpeg stderr: \${data}\`);
        });
    });
});

// Route to remove a stream
app.post('/remove-stream', (req, res) => {
    const streamName = req.body.streamName;
    const streamDir = path.join(streamsDir, streamName);

    fs.rmdir(streamDir, { recursive: true }, (err) => {
        if (err) {
            console.error('Error removing stream directory:', err);
            return res.status(500).send('Error removing stream');
        }
        console.log(\`Stream removed: \${streamName}\`);
        return res.redirect('/');
    });
});

// Start the server
app.listen(PORT, () => {
    console.log(\`Server is running on http://localhost:\${PORT}\`);
});
EOF

# Install necessary Node.js packages
echo "Installing required Node.js packages..."
cd /root/youtube-streamer
npm install express body-parser

# Start the server
echo "Starting the server..."
pm2 start server.js --name "youtube-streamer"
pm2 save

echo "Setup complete! The server is running."
