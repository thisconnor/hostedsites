import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Mia Swim — Private Swim Lessons',
  description:
    'Private 30-minute swim lessons with Mia. Book, reschedule, and pay online.',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
