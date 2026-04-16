import { motion } from 'motion/react';

interface Props {
  onDateSelect: (date: Date) => void;
}

export default function ReflectView({ onDateSelect }: Props) {
  const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  const calendarDays = [
    { day: 29, currentMonth: false, fullDate: '2026-03-29' },
    { day: 30, currentMonth: false, fullDate: '2026-03-30' },
    { day: 1, currentMonth: true, fullDate: '2026-04-01' },
    { day: 2, currentMonth: true, dot: true, fullDate: '2026-04-02' },
    { day: 3, currentMonth: true, fullDate: '2026-04-03' },
    { day: 4, currentMonth: true, fullDate: '2026-04-04' },
    { day: 5, currentMonth: true, fullDate: '2026-04-05' },
    { day: 6, currentMonth: true, fullDate: '2026-04-06' },
    { day: 7, currentMonth: true, dot: true, fullDate: '2026-04-07' },
    { day: 8, currentMonth: true, fullDate: '2026-04-08' },
    { day: 9, currentMonth: true, fullDate: '2026-04-09' },
    { day: 10, currentMonth: true, dot: true, fullDate: '2026-04-10' },
    { day: 11, currentMonth: true, fullDate: '2026-04-11' },
    { day: 12, currentMonth: true, fullDate: '2026-04-12' },
    { day: 13, currentMonth: true, fullDate: '2026-04-13' },
    { day: 14, currentMonth: true, dot: true, fullDate: '2026-04-14' },
    { day: 15, currentMonth: true, fullDate: '2026-04-15' },
    { day: 16, currentMonth: true, selected: true, fullDate: '2026-04-16' },
    { day: 17, currentMonth: true, dot: true, fullDate: '2026-04-17' },
    { day: 18, currentMonth: true, fullDate: '2026-04-18' },
    { day: 19, currentMonth: true, fullDate: '2026-04-19' },
    { day: 20, currentMonth: true, dot: true, fullDate: '2026-04-20' },
    { day: 21, currentMonth: true, fullDate: '2026-04-21' },
    { day: 22, currentMonth: true, dot: true, fullDate: '2026-04-22' },
    { day: 23, currentMonth: true, fullDate: '2026-04-23' },
    { day: 24, currentMonth: true, fullDate: '2026-04-24' },
    { day: 25, currentMonth: true, fullDate: '2026-04-25' },
    { day: 26, currentMonth: true, fullDate: '2026-04-26' },
    { day: 27, currentMonth: true, fullDate: '2026-04-27' },
    { day: 28, currentMonth: true, fullDate: '2026-04-28' },
    { day: 29, currentMonth: true, fullDate: '2026-04-29' },
    { day: 30, currentMonth: true, fullDate: '2026-04-30' },
    { day: 31, currentMonth: true, fullDate: '2026-04-31' },
    { day: 1, currentMonth: false, fullDate: '2026-05-01' },
    { day: 2, currentMonth: false, fullDate: '2026-05-02' },
  ];

  return (
    <div className="max-w-2xl mx-auto">
      <header className="mb-10 text-center">
        <h2 className="text-sm font-bold tracking-[0.2em] uppercase text-on-surface-variant">
          Select Date
        </h2>
      </header>

      <div className="bg-surface-container-low rounded-[2rem] p-6 md:p-10 shadow-sm border border-outline-variant">
        <div className="grid grid-cols-7 gap-y-2 text-center">
          {days.map(d => (
            <div key={d} className="text-[10px] font-bold text-on-surface-variant tracking-widest uppercase mb-4 opacity-40">
              {d}
            </div>
          ))}
          
          {calendarDays.map((date, i) => (
            <motion.div 
              key={i}
              whileTap={{ scale: 0.95 }}
              onClick={() => onDateSelect(new Date(date.fullDate))}
              className={`h-14 flex flex-col items-center justify-center relative cursor-pointer transition-all rounded-2xl
                ${!date.currentMonth ? 'text-on-surface-variant opacity-20' : 'text-on-surface font-semibold'}
                ${date.selected ? 'bg-gradient-to-br from-primary to-primary-container text-white shadow-xl shadow-primary/20 scale-110 z-10' : 'hover:bg-surface-container-high'}
              `}
            >
              <span>{date.day}</span>
              {date.dot && !date.selected && (
                <span className="absolute bottom-2 w-1 h-1 bg-primary rounded-full" />
              )}
            </motion.div>
          ))}
        </div>
      </div>
    </div>
  );
}
