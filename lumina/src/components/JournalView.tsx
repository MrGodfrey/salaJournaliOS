import { MEMORIES } from '../constants';
import MemoryCard from './MemoryCard';
import { Plus } from 'lucide-react';
import { motion } from 'motion/react';

interface Props {
  selectedDate: Date;
  onCalendarClick: () => void;
}

export default function JournalView({ selectedDate }: Props) {
  // Filter memories that match the month and day of selectedDate
  const filteredMemories = MEMORIES.filter(m => {
    const d = new Date(m.date);
    return d.getMonth() === selectedDate.getMonth() && d.getDate() === selectedDate.getDate();
  });

  // Group by year
  const groupedByYear = filteredMemories.reduce((acc, memory) => {
    const year = new Date(memory.date).getFullYear();
    if (!acc[year]) acc[year] = [];
    acc[year].push(memory);
    return acc;
  }, {} as Record<number, typeof MEMORIES>);

  const years = Object.keys(groupedByYear).sort((a, b) => Number(b) - Number(a));

  return (
    <div className="space-y-12">
      {years.length > 0 ? (
        years.map((yearStr) => {
          const year = Number(yearStr);
          return (
            <section key={year}>
              <h2 className="text-2xl font-headline font-extrabold text-on-surface tracking-tight mb-6 px-2">
                {year}
              </h2>
              <div className="grid gap-6">
                {groupedByYear[year].map((memory) => {
                  const dayName = new Intl.DateTimeFormat('en-US', { weekday: 'long' }).format(new Date(memory.date));
                  return (
                    <MemoryCard 
                      key={memory.id} 
                      memory={{
                        ...memory,
                        date: dayName // Only show weekday as requested
                      }} 
                    />
                  );
                })}
              </div>
            </section>
          );
        })
      ) : (
        <div className="text-center py-20 bg-surface-container-low rounded-3xl border border-outline-variant">
          <p className="text-on-surface-variant opacity-60 font-medium">No memories found for this day.</p>
        </div>
      )}

      <motion.button 
        whileHover={{ scale: 1.05 }}
        whileTap={{ scale: 0.95 }}
        className="fixed bottom-24 right-6 w-14 h-14 bg-gradient-to-br from-primary to-primary-container text-white rounded-full flex items-center justify-center shadow-lg shadow-primary/20 z-10"
      >
        <Plus size={28} />
      </motion.button>
    </div>
  );
}
