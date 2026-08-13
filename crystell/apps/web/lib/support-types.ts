export type SupportAttachment = {
  id: string;
  kind: "file" | "image" | "video";
  filename: string;
  content_type: string;
  byte_size: number;
};

export type SupportMessage = {
  id: string;
  author_type: "merchant" | "support" | "system";
  author_label?: string;
  body: string;
  created_at: string;
  attachments?: SupportAttachment[];
};

export type SupportTicket = {
  id: string;
  ticket_number: string;
  subject: string;
  priority: "low" | "normal" | "high" | "urgent";
  status: "open" | "pending" | "resolved" | "closed";
  source: "in_app" | "email" | "sms" | "whatsapp";
  last_message_at: string;
  created_at: string;
  messages?: SupportMessage[];
};
