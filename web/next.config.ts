import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async rewrites() {
    return {
      beforeFiles: [],
      // afterFiles runs only when no real file matched, so every asset in
      // public/app is still served directly and only the app's own routes
      // fall through to its index.html.
      afterFiles: [
        { source: "/app", destination: "/app/index.html" },
        { source: "/app/:path*", destination: "/app/index.html" },
      ],
      fallback: [],
    };
  },

  async headers() {
    return [
      {
        // The Flutter build is content-hashed by its own bootstrap, and the
        // screenshots never change under the same name.
        source: "/app/:path*",
        headers: [{ key: "Cache-Control", value: "public, max-age=3600, must-revalidate" }],
      },
      {
        source: "/screens/:path*",
        headers: [{ key: "Cache-Control", value: "public, max-age=31536000, immutable" }],
      },
      {
        source: "/downloads/:path*",
        headers: [{ key: "Cache-Control", value: "public, max-age=86400" }],
      },
    ];
  },
};

export default nextConfig;
