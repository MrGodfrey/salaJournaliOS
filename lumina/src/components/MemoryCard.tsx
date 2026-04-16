import { Memory } from '../types';
import { MoreHorizontal } from 'lucide-react';

interface Props {
  memory: Memory;
  key?: string | number;
}

export default function MemoryCard({ memory }: Props) {
  return (
    <div className="bg-surface-container-lowest rounded-xl overflow-hidden group cursor-pointer transition-transform active:scale-[0.98] border border-outline-variant">
      {memory.image && (
        <div className="aspect-[16/9] w-full overflow-hidden">
          <img 
            src={memory.image} 
            alt={memory.title} 
            className="w-full h-full object-cover transition-transform duration-500 group-hover:scale-105"
            referrerPolicy="no-referrer"
          />
        </div>
      )}
      <div className="p-5">
        <h3 className="text-lg font-headline font-bold text-on-surface mb-2">{memory.title}</h3>
        <p className="text-on-surface-variant font-sans text-sm leading-relaxed mb-4 line-clamp-2">
          {memory.excerpt}
        </p>
        <div className="flex justify-between items-center">
          <span className="text-[10px] text-on-surface-variant font-medium tracking-widest uppercase">{memory.date}</span>
          <button className="text-on-surface-variant/30 hover:text-primary transition-colors">
            <MoreHorizontal size={18} />
          </button>
        </div>
      </div>
    </div>
  );
}
