import React, { useState, useEffect, useCallback } from 'react';
import { RideRequest } from '../types';
import { api } from '../api';

interface DriverDashboardProps {
  onLogout: () => void;
  onGoToProfile: () => void;
  onAcceptRide: (ride: RideRequest) => Promise<void>;
  tripsToday: number;
}

export default function DriverDashboard({
  onGoToProfile,
  onAcceptRide,
  tripsToday,
}: DriverDashboardProps) {
  const [isAvailable, setIsAvailable] = useState(true);
  const [pendingRequests, setPendingRequests] = useState<RideRequest[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchPendingRides = useCallback(async () => {
    if (!isAvailable) {
      setPendingRequests([]);
      return;
    }
    try {
      const rides = await api.getPendingRides();
      setPendingRequests(
        rides.map((r) => ({
          id: r.id,
          from: r.from,
          to: r.to,
          passengerCount: r.passengerCount,
          status: r.status as RideRequest['status'],
          passengerName: r.passengerName || undefined,
        }))
      );
    } catch {
      // silently fail
    } finally {
      setLoading(false);
    }
  }, [isAvailable]);

  // Fetch pending rides on mount and poll every 5 seconds
  useEffect(() => {
    fetchPendingRides();
    const interval = setInterval(fetchPendingRides, 5000);
    return () => clearInterval(interval);
  }, [fetchPendingRides]);

  const handleToggleStatus = async () => {
    const newAvailable = !isAvailable;
    try {
      await api.setAvailability(newAvailable);
      setIsAvailable(newAvailable);
      if (!newAvailable) setPendingRequests([]);
    } catch {
      // If fails, don't toggle
    }
  };

  const handleAccept = async (ride: RideRequest) => {
    await onAcceptRide(ride);
    setPendingRequests((prev) => prev.filter((r) => r.id !== ride.id));
  };

  return (
    <div className="w-full bg-background min-h-screen flex flex-col pb-32 pt-20">
      {/* Top App Bar */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-white border-b border-outline-variant/30 flex justify-center items-center px-6 z-40 transition-colors duration-200">
        <h1 className="font-sans text-headline-lg font-bold text-primary text-center whitespace-nowrap">
          Schneider Park
        </h1>
      </header>

      {/* Main Container */}
      <main className="flex-grow w-full max-w-lg mx-auto px-6 flex flex-col gap-6">

        {/* Status Slider Toggle */}
        <div className="flex flex-col items-center gap-3">
          <h2 className="font-sans text-headline-md font-semibold text-on-background">
            Driver Dashboard
          </h2>

          <div
            onClick={handleToggleStatus}
            className="relative inline-flex items-center cursor-pointer bg-surface-container-high rounded-full p-1 shadow-[inset_0_2px_4px_rgba(0,0,0,0.06)] w-64 h-12 select-none"
          >
            <div
              className={`absolute top-1 bottom-1 w-[calc(50%-4px)] rounded-full shadow-sm transition-transform duration-300 ease-in-out ${
                isAvailable
                  ? 'translate-x-0 bg-primary-container'
                  : 'translate-x-full bg-surface-dim'
              }`}
            />
            <div
              className={`flex-1 text-center font-sans text-body-sm font-bold z-10 transition-colors duration-200 ${
                isAvailable ? 'text-on-primary-container' : 'text-on-surface-variant'
              }`}
            >
              Available
            </div>
            <div
              className={`flex-1 text-center font-sans text-body-sm font-bold z-10 transition-colors duration-200 ${
                !isAvailable ? 'text-on-surface-variant' : 'text-on-surface-variant/80'
              }`}
            >
              Busy
            </div>
          </div>
        </div>

        {/* Statistics Card */}
        <div className="bg-white rounded-2xl p-5 shadow-sm border border-outline-variant/30 flex justify-between items-center">
          <div className="flex flex-col gap-1">
            <span className="font-sans text-label-md text-on-surface-variant">Trips Today</span>
            <span className="font-sans text-headline-xl text-primary font-bold">{tripsToday}</span>
          </div>

          <div className="h-12 w-px bg-outline-variant/30" />

          <div className="flex flex-col items-end gap-1">
            <span className="font-sans text-label-md text-on-surface-variant">Current Occupancy</span>
            <div className="flex items-center gap-2">
              <span className="font-sans text-headline-xl text-on-background font-bold">0</span>
              <span className="font-sans text-body-lg text-on-surface-variant">/ 5</span>
              <span className="material-symbols-outlined text-primary-container">groups</span>
            </div>
          </div>
        </div>

        {/* Conditional Rendering: Available view vs Busy view */}
        {isAvailable ? (
          <div className="flex flex-col gap-4 fade-in-up">
            <div className="flex justify-between items-center mb-1">
              <h3 className="font-sans text-headline-md font-bold text-on-background">
                Pending Requests
              </h3>
              <span className="font-sans text-label-md text-primary bg-primary/10 px-3 py-1 rounded-full font-bold">
                {pendingRequests.length} New
              </span>
            </div>

            {loading ? (
              <div className="bg-white rounded-2xl p-8 text-center border border-outline-variant/30 shadow-xs flex flex-col items-center gap-3">
                <span className="material-symbols-outlined text-primary text-5xl animate-spin">progress_activity</span>
                <p className="font-sans text-body-lg text-on-surface-variant font-medium">Loading requests...</p>
              </div>
            ) : pendingRequests.length === 0 ? (
              <div className="bg-white rounded-2xl p-8 text-center border border-outline-variant/30 shadow-xs flex flex-col items-center gap-3">
                <span className="material-symbols-outlined text-outline text-5xl">task_alt</span>
                <p className="font-sans text-body-lg text-on-surface-variant font-medium">All requests cleared!</p>
                <p className="font-sans text-body-sm text-outline">You will be notified immediately of new incoming on-campus requests.</p>
              </div>
            ) : (
              pendingRequests.map((ride) => (
                <div
                  key={ride.id}
                  className="bg-white rounded-2xl p-5 shadow-sm border border-outline-variant/30 flex flex-col gap-4 relative overflow-hidden group hover:shadow-md transition-shadow duration-300"
                >
                  <div className="absolute top-0 left-0 w-1.5 h-full bg-primary" />

                  <div className="flex justify-between items-start pl-1">
                    <div className="flex flex-col gap-2">
                      <div className="flex items-center gap-2 text-on-background">
                        <span className="material-symbols-outlined text-primary text-lg !fill-1">
                          my_location
                        </span>
                        <span className="font-sans text-body-md font-bold">{ride.from}</span>
                      </div>
                      <div className="pl-[9px] h-3 border-l-2 border-dashed border-outline-variant/50 ml-1.5" />
                      <div className="flex items-center gap-2 text-on-background">
                        <span className="material-symbols-outlined text-error text-lg !fill-1">
                          location_on
                        </span>
                        <span className="font-sans text-body-md font-bold">{ride.to}</span>
                      </div>
                    </div>

                    <div className="flex flex-col items-end">
                      <span className="font-sans text-label-md text-on-surface-variant">Pooled</span>
                      <div className="flex items-center gap-1 text-secondary">
                        <span className="font-sans text-headline-md font-bold">{ride.passengerCount}</span>
                        <span className="material-symbols-outlined text-lg">person</span>
                      </div>
                    </div>
                  </div>

                  {ride.passengerName && (
                    <p className="font-sans text-body-sm text-on-surface-variant pl-1">
                      Passenger: <span className="font-bold text-on-surface">{ride.passengerName}</span>
                    </p>
                  )}

                  <button
                    onClick={() => handleAccept(ride)}
                    className="w-full bg-primary-container text-on-primary-container hover:bg-primary hover:text-white font-sans text-label-bold py-3.5 rounded-xl flex items-center justify-center gap-2 transition-colors active:scale-[0.98] cursor-pointer font-bold"
                  >
                    <span className="material-symbols-outlined text-lg font-bold">check_circle</span>
                    <span>Accept Request</span>
                  </button>
                </div>
              ))
            )}
          </div>
        ) : (
          <div className="bg-white rounded-2xl p-10 text-center border border-outline-variant/30 shadow-sm flex flex-col items-center justify-center gap-4 py-16 mt-4 fade-in-up">
            <div className="w-20 h-20 rounded-full bg-surface-container-high flex items-center justify-center text-on-surface-variant/40">
              <span className="material-symbols-outlined text-5xl">do_not_disturb_on</span>
            </div>
            <div className="space-y-1 max-w-xs">
              <h3 className="font-sans text-headline-md font-bold text-on-surface-variant">
                No new requests while busy
              </h3>
              <p className="font-sans text-body-md text-outline">
                Switch to 'Available' to receive new ride requests on campus.
              </p>
            </div>
          </div>
        )}
      </main>

      {/* Driver Bottom Navigation Bar */}
      <nav className="fixed bottom-0 left-0 right-0 h-20 bg-white border-t border-outline-variant/30 flex justify-around items-center px-4 pb-safe z-40">
        <button
          onClick={() => {}}
          className="flex flex-col items-center justify-center bg-primary-container text-on-primary-container rounded-full px-6 py-1 h-12 hover:opacity-95 active:scale-95 transition-all text-xs font-bold cursor-pointer gap-0.5"
        >
          <span className="material-symbols-outlined !text-[24px]">directions_car</span>
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
