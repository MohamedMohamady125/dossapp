import React from 'react';

interface SplashViewProps {
  onSelectRole: (role: 'employee' | 'driver') => void;
  onGoToLogin: () => void;
}

export default function SplashView({ onSelectRole, onGoToLogin }: SplashViewProps) {
  return (
    <div className="w-full max-w-[1280px] mx-auto min-h-screen flex flex-col justify-between pt-10 pb-16 px-6">
      {/* Upper Space / Branding */}
      <div className="flex-1 flex flex-col justify-center items-center text-center max-w-lg mx-auto">
        <div className="fade-in-up w-full max-w-[280px] mb-8">
          <img
            alt="Schneider Electric"
            className="w-full h-auto object-contain drop-shadow-sm select-none"
            src="https://lh3.googleusercontent.com/aida-public/AB6AXuBZuteS6yOZsbcDlr1QO0bZGE4Y3nJpmZ9_wv_4TuLGHUKQG3YLBIx3NJIgqt1AaPgIZykZRjkY3rOnf1orGl-zwH0Pu_4xJEpdhjTWkw3jcpfzs2HoBXkJZj8xT31-DNNMZ0AMCAzDuK4SUqzNqYheuiJskvTvGICygDn9-tc5rWwCrMQe7jzt5keK_-kCug_SF9itqwXtPg3iJe5uNtzZ9mVwJB4a_MJBOP_TLWdGAvldEsDf26kqUvfqwYeqCl3SrTdsU99tBUM"
          />
        </div>
        
        <div className="fade-in-up space-y-3 mt-4">
          <h1 className="font-sans text-4xl lg:text-5xl font-bold tracking-tight text-on-surface">
            Welcome to Park
          </h1>
          <p className="font-sans text-body-lg text-on-surface-variant max-w-sm mx-auto leading-relaxed">
            Smart, sustainable parking and campus transit management. Choose how to connect.
          </p>
        </div>
      </div>

      {/* Action Area (Bottom Heavy, Uber-style) */}
      <div className="w-full flex flex-col space-y-4 max-w-md mx-auto fade-in-up mt-8">
        
        {/* Primary Action: Employee */}
        <button
          onClick={() => onSelectRole('employee')}
          className="group w-full flex items-center justify-between px-6 py-5 rounded-full bg-primary-container text-on-primary-container hover:bg-primary hover:text-white transition-all duration-300 active:scale-[0.98] shadow-md hover:shadow-lg cursor-pointer"
        >
          <div className="flex items-center space-x-4">
            <div className="w-10 h-10 rounded-full bg-white/25 flex items-center justify-center backdrop-blur-sm group-hover:bg-white/40 transition-colors">
              <span className="material-symbols-outlined text-xl !fill-1 font-semibold">badge</span>
            </div>
            <span className="font-sans text-body-lg font-bold">Register as Employee</span>
          </div>
          <span className="material-symbols-outlined font-bold group-hover:translate-x-1.5 transition-transform">
            arrow_forward
          </span>
        </button>

        {/* Secondary Action: Driver */}
        <button
          onClick={() => onSelectRole('driver')}
          className="group w-full flex items-center justify-between px-6 py-5 rounded-full bg-inverse-surface text-surface-container-lowest hover:bg-on-background transition-all duration-300 active:scale-[0.98] shadow-md max-h-min hover:shadow-lg cursor-pointer"
        >
          <div className="flex items-center space-x-4">
            <div className="w-10 h-10 rounded-full bg-white/10 flex items-center justify-center group-hover:bg-white/20 transition-colors">
              <span className="material-symbols-outlined text-xl !fill-1 font-semibold">electric_car</span>
            </div>
            <span className="font-sans text-body-lg font-bold text-white">Register as Driver</span>
          </div>
          <span className="material-symbols-outlined font-bold text-white group-hover:translate-x-1.5 transition-transform">
            arrow_forward
          </span>
        </button>

        {/* Tertiary Action: Sign in */}
        <div className="pt-2 text-center">
          <button
            onClick={onGoToLogin}
            className="text-body-md text-on-surface-variant hover:text-primary transition-colors py-2 px-4 rounded-lg hover:bg-surface-container-low font-sans cursor-pointer"
          >
            Already have an account? <span className="font-bold text-primary">Sign in</span>
          </button>
        </div>
      </div>
    </div>
  );
}
