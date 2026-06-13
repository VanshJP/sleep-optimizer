import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Sleepytime",
  description:
    "Turn your WHOOP sleep history into a Sleepme / ChiliPad temperature schedule tuned to when you actually hit deep sleep and REM. 100% private — runs entirely in your browser.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
