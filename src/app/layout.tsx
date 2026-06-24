import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Personal Memory Wiki",
  description: "Private interface for the Supabase personal knowledge layer.",
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
