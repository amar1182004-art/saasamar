import type { ReactNode } from "react";
import "./globals.css";

export const metadata = {
  title: "Crystell",
  description: "Crystell commerce platform",
};

export default function RootLayout({ children }: Readonly<{ children: ReactNode }>) {
  return (
    <html lang="ar" dir="rtl">
      <body>{children}</body>
    </html>
  );
}
