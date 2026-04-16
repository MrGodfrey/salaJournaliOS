import { Search, ChevronDown } from 'lucide-react';
import { MEMORIES } from '../constants';
import MemoryCard from './MemoryCard';

export default function SearchView() {
  return (
    <div className="space-y-10">
      <div className="relative max-w-2xl mx-auto">
        <div className="absolute inset-y-0 left-6 flex items-center pointer-events-none text-on-surface/30">
          <Search size={20} />
        </div>
        <input 
          type="text" 
          defaultValue="Morning reflections"
          className="w-full h-14 pl-14 pr-6 bg-surface-container-low rounded-full border border-outline-variant focus:outline-none focus:ring-2 focus:ring-primary/20 text-on-surface font-sans placeholder:text-on-surface/30 transition-all"
          placeholder="Search your memories..."
        />
      </div>

      <div>
        <div className="mb-6 px-2">
          <p className="text-[10px] font-bold uppercase tracking-[0.2em] text-on-surface-variant/40 mb-1">Showing Results</p>
          <h2 className="text-3xl font-headline font-bold tracking-tight text-on-surface">Found 12 Memories</h2>
        </div>

        <div className="grid gap-6">
          {MEMORIES.map(memory => (
            <MemoryCard key={memory.id} memory={memory} />
          ))}
        </div>
      </div>

      <div className="flex justify-center pb-8 pt-4">
        <button className="px-8 py-3 bg-surface-container-low border border-outline-variant hover:bg-surface-container-high text-on-surface-variant font-bold uppercase tracking-widest text-[10px] rounded-full transition-all flex items-center gap-3">
          See older memories
          <ChevronDown size={14} />
        </button>
      </div>
    </div>
  );
}
