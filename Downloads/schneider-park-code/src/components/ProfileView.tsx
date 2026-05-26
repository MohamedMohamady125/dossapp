import React, { useState } from 'react';
import { UserProfile } from '../types';

interface ProfileViewProps {
  profile: UserProfile;
  onBack: () => void;
  onLogout: () => void;
  onUpdateName: (newName: string) => Promise<void>;
}

export default function ProfileView({
  profile,
  onBack,
  onLogout,
  onUpdateName,
}: ProfileViewProps) {
  const [editedName, setEditedName] = useState(profile.name);
  const [isSaved, setIsSaved] = useState(false);

  const handleSave = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await onUpdateName(editedName);
      setIsSaved(true);
      setTimeout(() => {
        setIsSaved(false);
      }, 2000);
    } catch {
      // silently fail
    }
  };

  return (
    <div className="w-full bg-background min-h-screen flex flex-col pb-32">
      {/* Top Header */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-white shadow-sm flex items-center px-6 z-50">
        <button
          onClick={onBack}
          aria-label="Go back"
          className="w-10 h-10 flex items-center justify-center rounded-full hover:bg-surface-variant/40 active:scale-95 transition-transform text-on-surface-variant absolute left-6 cursor-pointer"
        >
          <span className="material-symbols-outlined">arrow_back</span>
        </button>
        <h1 className="font-sans text-headline-md font-bold text-primary flex-1 text-center">
          Profile
        </h1>
      </header>

      {/* Main Container */}
      <main className="flex-1 w-full max-w-md mx-auto pt-20 px-6 flex flex-col gap-6">
        
        {/* Avatar Section */}
        <section className="flex flex-col items-center justify-center py-4">
          <div className="relative group">
            <div className="w-32 h-32 rounded-full overflow-hidden border-4 border-white shadow-md bg-surface-container flex items-center justify-center">
              <img
                alt="User Profile portrait shot"
                className="w-full h-full object-cover select-none"
                src="https://lh3.googleusercontent.com/aida-public/AB6AXuBoDcWIgvBetndrzDCVsCrhdJKa-cK7HFtjunmmGejgDV2A9zFYbtOMXaPaUtuADAJ9ag5AVrRUm3sbY7Qx239aTT-v-Whp4yLZ3LTuIeVkjWEl5GF8roEWQP3wShG8bRQZCfz1WkbDm0vek72IDq0rlcPUIII8saYV218ve0rTtgttf6XL594bx1M6LJvUpnFPJ-zWqX-JHuArecb5BD2-v0zHJIxkmgDlC-P3hdNV5S8U-uKo7XuC6yT__6pFHYUcB4lLj8asJYU"
              />
            </div>
            
            {/* Round Edit Badge indicator */}
            <button
              onClick={() => alert('Profile portrait customization is managed via corporate SSO credentials.')}
              aria-label="Edit avatar"
              className="absolute bottom-1 right-1 w-10 h-10 bg-primary-container text-on-primary-container rounded-full flex items-center justify-center shadow-md active:scale-95 transition-transform hover:bg-primary hover:text-white border-2 border-white cursor-pointer"
            >
              <span className="material-symbols-outlined text-[20px] font-bold">edit</span>
            </button>
          </div>
        </section>

        {/* Input Form Fields */}
        <form onSubmit={handleSave} className="flex flex-col gap-6">
          <div className="flex flex-col gap-5 bg-white p-6 rounded-2xl shadow-sm border border-outline-variant/30">
            
            {/* Editable Full Name */}
            <div className="flex flex-col gap-1.5">
              <label htmlFor="fullName" className="font-sans text-label-bold text-on-surface-variant ml-1 font-bold">
                Full Name
              </label>
              <div className="relative border border-outline-variant rounded-xl bg-white focus-within:ring-2 focus-within:ring-primary/20 focus-within:border-primary transition-all">
                <span className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-on-surface-variant">
                  <span className="material-symbols-outlined text-[20px]">person</span>
                </span>
                <input
                  id="fullName"
                  type="text"
                  value={editedName}
                  onChange={(e) => {
                    setEditedName(e.target.value);
                    setIsSaved(false);
                  }}
                  placeholder="Enter your full name"
                  className="w-full pl-11 pr-4 py-3 bg-transparent text-on-surface font-sans text-body-md focus:outline-none placeholder:text-outline border-none"
                />
              </div>
            </div>

            {/* Read-only Email Address */}
            <div className="flex flex-col gap-1.5">
              <span className="font-sans text-label-bold text-on-surface-variant ml-1 font-bold">
                Email Address
              </span>
              <div className="relative border border-transparent rounded-xl bg-surface-container-low opacity-80 cursor-not-allowed">
                <span className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-outline">
                  <span className="material-symbols-outlined text-[20px]">mail</span>
                </span>
                <input
                  type="email"
                  disabled
                  value={profile.email}
                  className="w-full pl-11 pr-4 py-3 bg-transparent text-on-surface-variant font-sans text-body-md border-none cursor-not-allowed outline-none"
                />
              </div>
            </div>

            {/* Read-only Phone Number */}
            <div className="flex flex-col gap-1.5">
              <span className="font-sans text-label-bold text-on-surface-variant ml-1 font-bold">
                Phone Number
              </span>
              <div className="relative border border-transparent rounded-xl bg-surface-container-low opacity-80 cursor-not-allowed">
                <span className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-outline">
                  <span className="material-symbols-outlined text-[20px]">phone</span>
                </span>
                <input
                  type="tel"
                  disabled
                  value={profile.phone}
                  className="w-full pl-11 pr-4 py-3 bg-transparent text-on-surface-variant font-sans text-body-md border-none cursor-not-allowed outline-none"
                />
              </div>
            </div>

            {/* Conditional vehicle identifier plate */}
            {profile.isDriver && profile.vehicleNumber && (
              <div className="flex flex-col gap-1.5">
                <span className="font-sans text-label-bold text-on-surface-variant ml-1 font-bold">
                  Active Shuttle Plate
                </span>
                <div className="relative border border-transparent rounded-xl bg-surface-container-low opacity-80 cursor-not-allowed">
                  <span className="absolute inset-y-0 left-0 pl-3.5 flex items-center pointer-events-none text-outline">
                    <span className="material-symbols-outlined text-[20px]">directions_car</span>
                  </span>
                  <input
                    type="text"
                    disabled
                    value={profile.vehicleNumber}
                    className="w-full pl-11 pr-4 py-3 bg-transparent text-on-surface-variant font-sans text-body-md border-none cursor-not-allowed outline-none font-bold uppercase"
                  />
                </div>
              </div>
            )}
          </div>

          {/* Action buttons list */}
          <div className="flex flex-col gap-4 mt-2">
            {editedName !== profile.name && (
              <button
                type="submit"
                className="w-full py-4 px-6 rounded-xl bg-primary text-white font-sans text-body-md font-bold hover:bg-opacity-90 active:scale-95 transition-all shadow-sm flex items-center justify-center gap-2 cursor-pointer"
              >
                <span className="material-symbols-outlined text-lg">save</span>
                Save Profile Changes
              </button>
            )}

            {isSaved && (
              <p className="text-center text-primary text-body-sm font-bold flex items-center justify-center gap-1.5">
                <span className="material-symbols-outlined text-sm">check_circle</span>
                Name updated successfully!
              </p>
            )}

            <button
              type="button"
              onClick={onLogout}
              className="w-full py-4 px-6 rounded-xl bg-error-container text-on-error-container font-sans text-body-md font-bold hover:bg-error-container/80 active:scale-[0.98] transition-all flex items-center justify-center gap-2 cursor-pointer"
            >
              <span className="material-symbols-outlined text-lg">logout</span>
              Log Out of Account
            </button>
          </div>
        </form>
      </main>

      {/* Profile Active Navigation Hub */}
      <nav className="fixed bottom-0 left-0 right-0 h-20 bg-white border-t border-outline-variant/30 flex justify-around items-center px-4 pb-safe z-40">
        <button
          onClick={onBack}
          className="flex flex-col items-center justify-center text-secondary hover:text-primary transition-colors h-12 px-6 py-1 text-xs font-medium cursor-pointer gap-0.5"
        >
          <span className="material-symbols-outlined !text-[24px]">
            {profile.isDriver ? 'directions_car' : 'electric_rickshaw'}
          </span>
          <span className="font-sans tracking-wide">Ride</span>
        </button>

        <button
          onClick={() => {}}
          className="flex flex-col items-center justify-center bg-primary-container text-on-primary-container rounded-full px-6 py-1 h-12 hover:opacity-95 active:scale-95 transition-all text-xs font-bold cursor-pointer gap-0.5"
        >
          <span className="material-symbols-outlined !text-[24px] !fill-1">person</span>
          <span className="font-sans tracking-wide">Profile</span>
        </button>
      </nav>
    </div>
  );
}
