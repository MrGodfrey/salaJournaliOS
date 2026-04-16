export type View = 'journal' | 'reflect' | 'search' | 'blog';

export interface Memory {
  id: string;
  title: string;
  excerpt: string;
  date: string;
  image?: string;
  tags?: string[];
}
