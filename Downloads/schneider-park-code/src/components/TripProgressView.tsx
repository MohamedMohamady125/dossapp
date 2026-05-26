import React, { useState, useEffect } from 'react';
import { RideRequest } from '../types';

interface TripProgressViewProps {
  ride: RideRequest;
  onCancel: () => void;
  onComplete: () => void;
  isDriverApp?: boolean;
}

export default function TripProgressView({
  ride,
  onCancel,
  onComplete,
  isDriverApp = false,
}: TripProgressViewProps) {
  // Simulate active state sequence: finding -> arriving -> onTheWay -> completed
  const [seqState, setSeqState] = useState<'finding' | 'arriving' | 'on_the_way' | 'arrived'>('finding');
  const [eta, setEta] = useState(3);
  const [markerProgress, setMarkerProgress] = useState(0); // 0 to 100% position on route

  useEffect(() => {
    // Stage 1: Finding appropriate driver (or accepting) -> moves fast
    const t1 = setTimeout(() => {
      setSeqState('arriving');
      setMarkerProgress(25);
    }, 2500);

    // Stage 2: Driver arriving
    const t2 = setTimeout(() => {
      setSeqState('on_the_way');
      setEta(1);
      setMarkerProgress(60);
    }, 7000);

    // Stage 3: Arrived
    const t3 = setTimeout(() => {
      setSeqState('arrived');
      setEta(0);
      setMarkerProgress(100);
    }, 13000);

    // Smoothly animate marker position progress slightly over time
    const interval = setInterval(() => {
      setMarkerProgress((prev) => {
        if (prev >= 100) return 100;
        return prev + 1;
      });
    }, 200);

    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
      clearTimeout(t3);
      clearInterval(interval);
    };
  }, []);

  // Compute animated position of marker on S-curve mapping function
  // Simple trigonometric path curve representation for moving visual indicators
  const getPositionOnPath = (pct: number) => {
    // Width and height ratios mapped to S-shaped path preview
    const t = pct / 100;
    // S-curve interpolation
    const startX = 20;
    const endX = 80;
    const startY = 80;
    const endY = 20;

    const x = startX + (endX - startX) * t;
    // Cubic bezier or sine interpolation for realistic curved alignment
    const y = startY + (endY - startY) * t - Math.sin(t * Math.PI) * 15;
    
    return { left: `${x}%`, top: `${y}%` };
  };

  const currentPosStyles = getPositionOnPath(markerProgress);

  const getStatusText = () => {
    if (seqState === 'finding') return 'Locating available golf car...';
    if (seqState === 'arriving') return isDriverApp ? 'Drive to pickup pavilion' : 'Driver is arriving';
    if (seqState === 'on_the_way') return 'On-campus transfer in progress';
    return 'Arrived at your destination';
  };

  const getEtaSubtitle = () => {
    if (seqState === 'finding') return 'Assigning nearest dispatcher';
    if (seqState === 'arriving') return `${eta} mins • Sam is 100m away`;
    if (seqState === 'on_the_way') return 'Transit is active • Eco-friendly power on';
    return 'Green drive complete • Thank you!';
  };

  return (
    <div className="w-full bg-[#f4fcee] min-h-screen flex flex-col overflow-hidden">
      {/* Top Header */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-white border-b border-outline-variant/30 flex justify-center items-center px-6 z-40">
        <div className="flex items-center gap-2">
          <span className="material-symbols-outlined text-primary text-2xl">electric_rickshaw</span>
          <h1 className="font-sans text-headline-lg font-bold text-primary">Schneider Park</h1>
        </div>
      </header>

      {/* Main Content Visual Area */}
      <main className="flex-1 flex flex-col mt-16 relative">
        {/* Map Canvas Frame */}
        <div className="relative w-full h-[50vh] bg-[#dde5d7]/50 overflow-hidden border-b border-outline-variant/20 select-none">
          {/* Map Grid Pattern background */}
          <div className="absolute inset-0 bg-grid-pattern opacity-60" />
          
          {/* Ambient Map Gradients for absolute layout clarity */}
          <div className="absolute inset-0 bg-gradient-to-b from-white/30 via-transparent to-white/40 pointer-events-none" />

          {/* Route S-curve Dotted Line Rendering */}
          <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-[85%] h-[65%] pointer-events-none">
            
            <svg className="absolute inset-0 w-full h-full" preserveAspectRatio="none" viewBox="0 0 100 100">
              <path
                d="M 20,80 Q 40,80 50,50 T 80,20"
                fill="none"
                stroke="#3dcd58"
                strokeWidth="4"
                strokeDasharray="8,8"
                className="opacity-70"
              />
            </svg>

            {/* Start Point marker (e.g. Origin) */}
            <div className="absolute bottom-[20%] left-[20%] flex flex-col items-center transform -translate-x-1/2 translate-y-1/2">
              <div className="w-5 h-5 rounded-full bg-outline-variant flex items-center justify-center shadow-md border-2 border-white">
                <div className="w-2.5 h-2.5 rounded-full bg-secondary" />
              </div>
              <span className="mt-1 font-sans text-label-bold text-on-surface-variant bg-white/95 px-2.5 py-1 rounded-full text-[10px] shadow-xs border border-outline-variant/20">
                {ride.from}
              </span>
            </div>

            {/* End Point marker (e.g. Destination) */}
            <div className="absolute top-[20%] right-[20%] flex flex-col items-center transform translate-x-1/2 -translate-y-1/2">
              <div className="w-6 h-6 rounded-full bg-secondary flex items-center justify-center shadow-md border-2 border-white">
                <span className="material-symbols-outlined text-white text-[12px]">business</span>
              </div>
              <span className="mt-1 font-sans text-label-bold text-on-surface-variant bg-white/95 px-2.5 py-1 rounded-full text-[10px] shadow-xs border border-outline-variant/20">
                {ride.to}
              </span>
            </div>

            {/* Actively Animated Moving Vehicle Pulse marker */}
            <div
              className="absolute transform -translate-x-1/2 -translate-y-1/2 pulse-marker z-20 transition-all duration-300 pointer-events-auto"
              style={currentPosStyles}
            >
              <div className="w-12 h-12 rounded-full bg-primary flex items-center justify-center shadow-lg border-2 border-white cursor-pointer">
                <span className="material-symbols-outlined text-white text-2xl !fill-1">
                  electric_rickshaw
                </span>
              </div>
            </div>
          </div>
        </div>

        {/* Trip Details bottom interactive card sheet */}
        <div className="flex-1 bg-white rounded-t-3xl shadow-[0_-8px_24px_rgba(10,47,36,0.08)] z-10 -mt-6 px-6 pt-6 pb-28 flex flex-col gap-5 relative">
          
          {/* Accent drag handle bar indicator */}
          <div className="w-12 h-1.5 bg-outline-variant rounded-full mx-auto mb-1 animate-pulse" />

          {/* Heading dynamic ETA counter */}
          <div className="flex flex-col items-center text-center">
            <h2 className="font-sans text-4xl font-bold text-primary tracking-tight">
              {seqState === 'finding' ? 'Matching...' : seqState === 'arrived' ? 'Arrived' : `${eta} mins`}
            </h2>
            <p className="font-sans text-body-lg text-on-surface font-semibold mt-1">
              {getStatusText()}
            </p>
            <p className="font-sans text-body-sm text-on-surface-variant mt-0.5">
              {getEtaSubtitle()}
            </p>
          </div>

          <hr className="border-outline-variant/20" />

          {/* Context Card Block: Driver information modules */}
          <div className="bg-surface-container-low/40 p-4 rounded-2xl border border-outline-variant/20 flex items-center justify-between shadow-xs">
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 rounded-full overflow-hidden bg-secondary-container flex items-center justify-center shrink-0 border border-primary/10">
                <img
                  alt="Sam profile avatar shot"
                  className="w-full h-full object-cover"
                  src="https://lh3.googleusercontent.com/aida-public/AB6AXuBoDcWIgvBetndrzDCVsCrhdJKa-cK7HFtjunmmGejgDV2A9zFYbtOMXaPaUtuADAJ9ag5AVrRUm3sbY7Qx239aTT-v-Whp4yLZ3LTuIeVkjWEl5GF8roEWQP3wShG8bRQZCfz1WkbDm0vek72IDq0rlcPUIII8saYV218ve0rTtgttf6XL594bx1M6LJvUpnFPJ-zWqX-JHuArecb5BD2-v0zHJIxkmgDlC-P3hdNV5S8U-uKo7XuC6yT__6pFHYUcB4lLj8asJYU"
                />
              </div>

              <div>
                <h3 className="font-sans text-body-lg font-bold text-on-surface">
                  {isDriverApp ? (ride.passengerName || 'David Mitchell') : 'Sam Watson'}
                </h3>
                <div className="flex items-center gap-1.5 text-secondary">
                  <span className="material-symbols-outlined text-sm !fill-1">star</span>
                  <span className="font-sans text-label-bold">4.9 Campus Score</span>
                </div>
              </div>
            </div>

            {/* Vehicle configuration block */}
            <div className="flex flex-col items-end">
              <div className="bg-white border border-outline-variant/40 px-3 py-1.5 rounded-xl shadow-xs flex flex-col items-center min-w-[70px]">
                <span className="font-sans text-[9px] font-bold text-on-surface-variant uppercase tracking-wider">
                  Vehicle
                </span>
                <span className="font-sans text-body-md font-bold text-primary leading-none mt-0.5">
                  #04
                </span>
              </div>
            </div>
          </div>

          {/* Interactive buttons */}
          <div className="flex gap-4 mt-auto">
            {seqState !== 'arrived' ? (
              <>
                <button
                  type="button"
                  onClick={onCancel}
                  className="flex-1 py-3.5 px-4 rounded-full border border-error text-error bg-error-container/10 hover:bg-error-container/30 transition-all font-sans text-label-bold flex items-center justify-center gap-2 cursor-pointer font-bold active:scale-95"
                >
                  <span className="material-symbols-outlined text-lg">close</span>
                  Cancel Ride
                </button>
                <button
                  type="button"
                  onClick={() => alert('Initiating priority VOIP phone connection to dispatcher...')}
                  className="flex-1 py-3.5 px-4 rounded-full bg-primary-container text-on-primary-container hover:bg-primary hover:text-white transition-all font-sans text-label-bold flex items-center justify-center gap-2 cursor-pointer font-bold active:scale-95 shadow-sm"
                >
                  <span className="material-symbols-outlined text-lg !fill-1">call</span>
                  {isDriverApp ? 'Call Passenger' : 'Call Dispatch'}
                </button>
              </>
            ) : (
              <button
                type="button"
                onClick={onComplete}
                className="w-full py-4 px-6 rounded-xl bg-primary text-white hover:bg-on-tertiary-container transition-all font-sans text-body-md font-bold flex items-center justify-center gap-2 cursor-pointer shadow-md active:scale-95 animate-bounce"
              >
                <span className="material-symbols-outlined text-lg">task_alt</span>
                Dismiss &amp; Complete Transit
              </button>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}
