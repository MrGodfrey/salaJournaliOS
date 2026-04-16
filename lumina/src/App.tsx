/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState } from 'react';
import { View } from './types';
import JournalView from './components/JournalView';
import ReflectView from './components/ReflectView';
import SearchView from './components/SearchView';
import BlogView from './components/BlogView';
import { X, Calendar, Search, BookOpen, Clock, FileText } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';

export default function App() {
  const [currentView, setCurrentView] = useState<View>('journal');
  const [selectedDate, setSelectedDate] = useState<Date>(new Date('2026-04-16')); // Simulation date

  const handleDateSelect = (date: Date) => {
    setSelectedDate(date);
    setCurrentView('journal');
  };

  const renderView = () => {
    switch (currentView) {
      case 'journal': 
        return <JournalView selectedDate={selectedDate} onCalendarClick={() => setCurrentView('reflect')} />;
      case 'reflect': 
        return <ReflectView onDateSelect={handleDateSelect} />;
      case 'search': 
        return <SearchView />;
      case 'blog': 
        return <BlogView />;
      default: 
        return <JournalView selectedDate={selectedDate} onCalendarClick={() => setCurrentView('reflect')} />;
    }
  };

  const formattedHeaderDate = `${selectedDate.getMonth() + 1}月${selectedDate.getDate()}`;

  return (
    <div className="min-h-screen bg-background text-on-surface pb-32">
      {/* Top Bar */}
      <header className="glass fixed top-0 left-0 w-full h-16 z-50 transition-all duration-300">
        <div className="max-w-7xl mx-auto px-6 h-full flex justify-between items-center">
          <div className="flex items-center gap-3">
            {currentView === 'journal' ? (
              <>
                <button 
                  onClick={() => setCurrentView('reflect')}
                  className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-surface-container-high transition-colors active:scale-95"
                >
                  <Calendar size={20} />
                </button>
                <h2 className="font-headline font-extrabold text-2xl tracking-tight text-on-surface">
                  {formattedHeaderDate}
                </h2>
              </>
            ) : (
              <button 
                onClick={() => setCurrentView('journal')}
                className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-surface-container-high transition-colors active:scale-95"
              >
                <X size={20} />
              </button>
            )}
          </div>
          
          <h1 className="absolute left-1/2 -translate-x-1/2 font-headline font-extrabold text-xl tracking-tighter text-primary pointer-events-none">
            Lumina
          </h1>
          
          <div className="flex items-center gap-1">
            {currentView === 'journal' ? (
               <button 
                 onClick={() => setCurrentView('search')}
                 className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-surface-container-high transition-colors active:scale-95"
               >
                 <Search size={20} />
               </button>
            ) : (
               <div className="flex gap-1 p-4">
                 <div className="w-1 h-1 bg-on-surface rounded-full opacity-30" />
                 <div className="w-1 h-1 bg-on-surface rounded-full opacity-30" />
                 <div className="w-1 h-1 bg-on-surface rounded-full opacity-30" />
               </div>
            )}
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-6 pt-24 pb-12">
        <AnimatePresence mode="wait">
          <motion.div
            key={currentView}
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.3, ease: [0.23, 1, 0.32, 1] }}
          >
            {renderView()}
          </motion.div>
        </AnimatePresence>
      </main>

      {/* Navigation Bar */}
      <nav className="fixed bottom-0 left-0 w-full z-50 glass rounded-t-[2.5rem] shadow-[0_-10px_40px_rgba(46,51,54,0.05)] border-t-0 p-2 md:p-3">
        <div className="max-w-lg mx-auto flex justify-around items-center px-2 pb-6 pt-2">
          <NavButton 
            icon={<BookOpen size={24} />} 
            label="Journal" 
            active={currentView === 'journal'} 
            onClick={() => setCurrentView('journal')} 
          />
          <NavButton 
            icon={<Clock size={24} />} 
            label="Reflect" 
            active={currentView === 'reflect'} 
            onClick={() => setCurrentView('reflect')} 
          />
          <NavButton 
            icon={<Search size={24} />} 
            label="Search" 
            active={currentView === 'search'} 
            onClick={() => setCurrentView('search')} 
          />
          <NavButton 
            icon={<FileText size={24} />} 
            label="Blog" 
            active={currentView === 'blog'} 
            onClick={() => setCurrentView('blog')} 
          />
        </div>
      </nav>
    </div>
  );
}

interface NavButtonProps {
  icon: React.ReactNode;
  label: string;
  active?: boolean;
  onClick: () => void;
}

function NavButton({ icon, label, active, onClick }: NavButtonProps) {
  return (
    <button 
      onClick={onClick}
      className={`relative flex flex-col items-center justify-center p-3 transition-all duration-300 group
        ${active ? 'text-white scale-110 z-10' : 'text-on-surface-variant/40 hover:text-primary'}
      `}
    >
      {active && (
        <motion.div 
          layoutId="nav-bg"
          className="absolute inset-0 bg-gradient-to-br from-primary to-primary-container rounded-2xl shadow-lg shadow-primary/20"
        />
      )}
      <span className="relative z-10 mb-1 transition-transform group-hover:scale-110">
        {icon}
      </span>
      <span className="relative z-10 font-sans text-[9px] font-bold tracking-widest uppercase mt-0.5">
        {label}
      </span>
    </button>
  );
}
