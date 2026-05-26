import React, { useState } from 'react';
import { CampusLocation } from '../types';

interface EmployeeDashboardProps {
  onLogout: () => void;
  onRequestRide: (passengers: number, from: string, to: string) => Promise<void>;
  onGoToProfile: () => void;
  userName: string;
}

const CAMPUS_LOCATIONS: CampusLocation[] = [
  {
    id: 'office',
    name: 'Office',
    description: 'Main Campus Building',
    icon: 'business',
  },
  {
    id: 'parking',
    name: 'Parking',
    description: 'Corporate Parking Zone',
    icon: 'local_parking',
  },
];

export default function EmployeeDashboard({
  onRequestRide,
  onGoToProfile,
  userName,
}: EmployeeDashboardProps) {
  const [passengers, setPassengers] = useState(1);
  const [pickup, setPickup] = useState('parking');
  const [destination, setDestination] = useState('office');
  const [locationError, setLocationError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const handleRequestSubmit = async () => {
    setLocationError('');
    if (pickup === destination) {
      setLocationError('Pickup location and Destination cannot be the same.');
      return;
    }

    const fromLoc = CAMPUS_LOCATIONS.find((l) => l.id === pickup)?.name || pickup;
    const toLoc = CAMPUS_LOCATIONS.find((l) => l.id === destination)?.name || destination;

    setSubmitting(true);
    try {
      await onRequestRide(passengers, fromLoc, toLoc);
    } catch (err: any) {
      setLocationError(err.message || 'Failed to request ride.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="w-full bg-background min-h-screen flex flex-col bg-grid-pattern pb-32">
      {/* Top App Bar */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-white border-b border-outline-variant/30 flex justify-center items-center px-6 z-40 transition-colors duration-200">
        <h1 className="font-sans text-headline-md font-bold text-primary text-center">
          Schneider Park
        </h1>
      </header>

      {/* Main Container */}
      <main className="flex-1 w-full max-w-2xl mx-auto pt-20 px-6 flex flex-col gap-6">
        
        {/* Welcome Section */}
        <section className="mt-4">
          <div className="flex justify-between items-center">
            <div>
              <h2 className="font-sans text-3xl font-bold text-on-surface tracking-tight">
                Request Golf Car
              </h2>
              <p className="font-sans text-body-md text-on-surface-variant mt-1">
                Arrange a sustainable on-campus ride, {userName}.
              </p>
            </div>
            <span className="material-symbols-outlined text-primary text-4xl p-2 bg-primary/5 rounded-full">
              electric_rickshaw
            </span>
          </div>
        </section>

        {locationError && (
          <div className="p-4 rounded-xl bg-error-container text-on-error-container text-body-sm font-medium border border-error/20 flex items-center gap-2">
            <span className="material-symbols-outlined text-lg">error</span>
            {locationError}
          </div>
        )}

        {/* Bento Passenger Selector */}
        <section className="bg-white rounded-2xl p-5 shadow-sm border border-outline-variant/30 relative overflow-hidden">
          <div className="absolute -right-4 -top-4 text-surface-container w-24 h-24 opacity-25 pointer-events-none">
            <span className="material-symbols-outlined text-7xl !fill-1">groups</span>
          </div>

          <h3 className="font-sans text-body-lg text-on-surface font-semibold mb-4 flex items-center gap-2">
            <span className="material-symbols-outlined text-primary">person</span>
            Number of Passengers
          </h3>

          <div className="flex gap-2.5 justify-between">
            {[1, 2, 3, 4, 5].map((num) => {
              const isActive = passengers === num;
              return (
                <button
                  key={num}
                  type="button"
                  onClick={() => setPassengers(num)}
                  className={`flex-1 aspect-square rounded-xl flex items-center justify-center font-sans text-headline-md font-bold transition-all duration-200 cursor-pointer ${
                    isActive
                      ? 'bg-primary-container text-on-primary-container border-2 border-primary shadow-[0_4px_12px_rgba(61,205,88,0.25)]'
                      : 'border border-outline-variant/60 bg-surface/50 text-on-surface-variant hover:bg-surface-container'
                  }`}
                >
                  {num}
                </button>
              );
            })}
          </div>
        </section>

        {/* Route selector: Pickup Location with Dynamic Auto-Opposite Destination */}
        <section className="bg-white rounded-2xl p-5 shadow-sm border border-outline-variant/30 flex flex-col gap-5">
          <h3 className="font-sans text-body-lg text-on-surface font-semibold flex items-center gap-2">
            <span className="material-symbols-outlined text-primary">location_on</span>
            Select Logistics Parameters
          </h3>

          <div className="flex flex-col gap-4">
            <div>
              <label className="text-xs font-bold text-on-surface-variant uppercase tracking-wider block mb-2 px-1">
                Pickup Location
              </label>
              <div className="grid grid-cols-2 gap-4">
                {CAMPUS_LOCATIONS.map((loc) => {
                  const isChecked = pickup === loc.id;
                  return (
                    <label
                      key={`pickup-${loc.id}`}
                      className={`flex items-center justify-between p-4 rounded-xl border cursor-pointer transition-all duration-200 ${
                        isChecked
                          ? 'border-primary bg-primary/5 font-bold'
                          : 'border-outline-variant/50 hover:border-primary/50 bg-white'
                      }`}
                    >
                      <div className="flex items-center gap-3">
                        <div className={`w-10 h-10 rounded-full flex items-center justify-center transition-colors ${
                          isChecked ? 'bg-primary text-white' : 'bg-surface-container-high text-on-surface-variant'
                        }`}>
                          <span className="material-symbols-outlined text-xl">
                            {loc.icon}
                          </span>
                        </div>
                        <div>
                          <span className="font-sans text-body-md font-bold text-on-surface block">
                            {loc.name}
                          </span>
                          <span className="font-sans text-[11px] text-on-surface-variant block">
                            {loc.description}
                          </span>
                        </div>
                      </div>
                      <input
                        type="radio"
                        name="pickup-location"
                        value={loc.id}
                        checked={isChecked}
                        onChange={() => {
                          setPickup(loc.id);
                          setDestination(loc.id === 'office' ? 'parking' : 'office');
                        }}
                        className="w-4 h-4 text-primary focus:ring-primary-container border-outline-variant"
                      />
                    </label>
                  );
                })}
              </div>
            </div>

            {/* Auto-opposite Destination Display */}
            <div className="bg-[#f4fcee] p-4 rounded-xl border border-primary/10 flex items-center justify-between shadow-xs">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-primary/10 text-primary flex items-center justify-center">
                  <span className="material-symbols-outlined text-xl">
                    {destination === 'office' ? 'business' : 'local_parking'}
                  </span>
                </div>
                <div>
                  <span className="text-xs font-bold text-on-surface-variant uppercase tracking-wider block">
                    Dropoff Destination (Auto-filled)
                  </span>
                  <span className="font-sans text-body-md font-bold text-primary">
                    {destination === 'office' ? 'Office' : 'Parking'}
                  </span>
                </div>
              </div>
              <div className="flex items-center gap-1.5 text-primary text-body-xs font-semibold bg-white/60 px-2.5 py-1 rounded-full border border-primary/5">
                <span className="material-symbols-outlined text-xs animate-pulse">check_circle</span>
                Opposite Synced
              </div>
            </div>
          </div>
        </section>

        {/* Static Map Visual Overlay indicator */}
        <div className="rounded-2xl overflow-hidden h-36 relative border border-outline-variant/30 shadow-sm">
          <div
            className="absolute inset-0 bg-cover bg-center select-none"
            style={{
              backgroundImage: `url('https://lh3.googleusercontent.com/aida-public/AB6AXuAvLqtHhjQj8iSVpNf4HhvYHkB2gw6ZbFyFV3XwxDqdDSrBy1-8inxsQesFJA_Y2Eimvovs6ja6TuFfHwVe4ewSeARqmy473ifKdYaGSnP9oVRfHfHUxmGE1sbC3mZCs1oJeK3g4L4hHonXIMF41btjIq6TCkdiA-l-qH03pKe2FU14ECuiBMA9EA8v_-d1IUtgAcLA6eTAcF1Tq52i00veBUVHSt8Il1IUvl2ssAO5ccVicipSM6Hoe-kzEYxuHT2cYC-q6SNmBus')`
            }}
          />
          <div className="absolute inset-0 bg-gradient-to-t from-[#161d15]/80 to-transparent flex items-end p-4">
            <span className="font-sans text-body-sm text-white font-medium flex items-center gap-1.5">
              <span className="material-symbols-outlined text-sm text-primary-container">my_location</span>
              Campus Live Transit Map Active
            </span>
          </div>
        </div>

      </main>

      {/* Prominent Floating Action Sticky Area */}
      <div className="fixed bottom-[80px] w-full px-6 pb-2 z-30 max-w-2xl left-1/2 transform -translate-x-1/2">
        <button
          onClick={handleRequestSubmit}
          disabled={submitting}
          className="w-full bg-primary-container text-on-primary-container font-sans text-headline-md py-4 rounded-full shadow-[0_8px_24px_rgba(10,47,36,0.15)] flex justify-center items-center gap-2 hover:bg-primary hover:text-white transition-all duration-200 active:scale-95 cursor-pointer disabled:opacity-50"
        >
          {submitting ? (
            <span className="material-symbols-outlined text-lg animate-spin">progress_activity</span>
          ) : (
            <>
              <span>Request Golf Car</span>
              <span className="material-symbols-outlined">electric_rickshaw</span>
            </>
          )}
        </button>
      </div>

      {/* Styled Mobile Navigation bar */}
      <nav className="fixed bottom-0 left-0 right-0 h-20 bg-white border-t border-outline-variant/30 flex justify-around items-center px-4 pb-safe z-40">
        <button
          onClick={() => {}} // Dynamic switch or scroll back
          className="flex flex-col items-center justify-center bg-primary-container text-on-primary-container rounded-full px-6 py-1 h-12 hover:opacity-90 active:scale-95 transition-all text-xs font-bold cursor-pointer gap-0.5"
        >
          <span className="material-symbols-outlined !text-[24px]">electric_rickshaw</span>
          <span className="font-sans tracking-wide">Ride</span>
        </button>

        <button
          onClick={onGoToProfile}
          className="flex flex-col items-center justify-center text-secondary hover:text-primary transition-colors h-12 px-6 py-1 text-xs font-medium cursor-pointer gap-0.5"
        >
          <span className="material-symbols-outlined !text-[24px]">person</span>
          <span className="font-sans tracking-wide">Profile</span>
        </button>
      </nav>
    </div>
  );
}
