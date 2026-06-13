import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          // Lock the app down: no outbound connections allowed at all, so user
          // data physically cannot be exfiltrated even if a bad script got in.
          {
            key: "Content-Security-Policy",
            value: [
              "default-src 'self'",
              "script-src 'self' 'unsafe-inline'",
              "style-src 'self' 'unsafe-inline'",
              "img-src 'self' data:",
              // 'self' is needed in dev for hot reload; in production the app
              // makes zero requests after load either way.
              process.env.NODE_ENV === "development"
                ? "connect-src 'self' ws: wss:"
                : "connect-src 'none'",
              "object-src 'none'",
              "base-uri 'self'",
              "form-action 'none'",
              "frame-ancestors 'none'",
            ].join("; "),
          },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "X-Frame-Options", value: "DENY" },
          { key: "Referrer-Policy", value: "no-referrer" },
          { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
        ],
      },
    ];
  },
};

export default nextConfig;
