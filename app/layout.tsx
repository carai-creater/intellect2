import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ラーニングチューター",
  description: "シンプルなラーニングチューター — 教材とチャットで学ぶ",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ja">
      <body>{children}</body>
    </html>
  );
}
