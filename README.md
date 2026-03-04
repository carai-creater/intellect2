# intellect2

- **Native app (iOS + macOS):** [SimpleLearningTutor](./SimpleLearningTutor/README.md) — SwiftUI app with Dify chat + file upload.
- **Web (Vercel):** Next.js Learning Tutor — same flow in the browser, deployable on Vercel.

---

## Deploy the web app on Vercel

1. **Push this repo to GitHub** (if you haven’t already).

2. **Import on Vercel**
   - Go to [vercel.com](https://vercel.com) → **Add New…** → **Project**.
   - Import the `intellect2` repo (or your fork).
   - Vercel will detect the Next.js app at the repo root.

3. **Set environment variables** (Vercel project → **Settings** → **Environment Variables**):
   - `DIFY_BASE_URL` — your Dify API base URL (e.g. `https://api.dify.ai/v1`).
   - `DIFY_API_KEY` — your Dify API key.

4. **Deploy**  
   Click **Deploy**. The app will be available at `https://your-project.vercel.app`.

### Run locally

```bash
npm install
cp .env.example .env
# Edit .env with your DIFY_BASE_URL and DIFY_API_KEY
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).