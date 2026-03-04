import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Learning Tutor",
  description: "Simple Learning Tutor — chat with your study materials",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
