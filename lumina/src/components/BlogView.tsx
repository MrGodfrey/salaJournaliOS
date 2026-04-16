import { STORIES } from '../constants';
import MemoryCard from './MemoryCard';

export default function BlogView() {
  return (
    <div className="space-y-10">
      <header className="px-2">
        <p className="text-[10px] font-bold tracking-widest uppercase text-primary mb-1">Our Journal</p>
        <h2 className="font-headline text-5xl font-extrabold tracking-tight text-on-surface leading-none">
          Stories &<br />Reflections
        </h2>
      </header>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {STORIES.map(story => (
          <MemoryCard key={story.id} memory={story} />
        ))}
      </div>
    </div>
  );
}
