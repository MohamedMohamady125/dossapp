import React, { useState } from 'react';

interface DriverRegistrationViewProps {
  onBack: () => void;
  onSubmit: (data: { name: string; phone: string; vehicleNumber: string }) => Promise<void>;
}

export default function DriverRegistrationView({ onBack, onSubmit }: DriverRegistrationViewProps) {
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [vehicleNumber, setVehicleNumber] = useState('');
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!name.trim()) {
      setError('Please enter your full name.');
      return;
    }
    if (!phone.trim()) {
      setError('Please enter your phone number.');
      return;
    }
    if (!vehicleNumber.trim()) {
      setError('Please enter your Vehicle Number or License Plate.');
      return;
    }

    setSubmitting(true);
    try {
      await onSubmit({
        name,
        phone,
        vehicleNumber: vehicleNumber.toUpperCase(),
      });
    } catch (err: any) {
      setError(err.message || 'Registration failed. Please try again.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="w-full max-w-md mx-auto min-h-screen flex flex-col pt-20 pb-12 px-6">
      {/* Fixed top Header */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-surface/90 backdrop-blur-md z-50 flex items-center justify-between border-b border-outline-variant/30 px-6">
        <button
          onClick={onBack}
          aria-label="Go back"
          className="text-primary hover:bg-surface-container-low p-2 rounded-full transition-colors flex items-center justify-center cursor-pointer"
        >
          <span className="material-symbols-outlined">arrow_back</span>
        </button>
        <span className="font-sans text-headline-md font-bold text-primary absolute left-1/2 -translate-x-1/2">
          Driver Registration
        </span>
        <div className="w-10"></div>
      </header>

      {/* Main Form Fields */}
      <div className="flex-1 flex flex-col justify-start">
        {/* Subtle Brand Logo */}
        <div className="flex justify-center py-6 mb-2">
          <img
            alt="Schneider Electric Logo"
            className="h-10 object-contain opacity-80 select-none"
            src="https://lh3.googleusercontent.com/aida-public/AB6AXuAzJjw3l1TjR2ejiMlHnlNFS1M3TmElcpUsSwcxGKYQgGyNxyhWkwx-IaXSG6Lc8fx3vD85och76_LHVvefJVct6LUW5-Pf8M3hVmCnksJBbccdeaVyFgnmjtHP5il3WNKnhSQuJc7VZV3Bh5SbCkl_6IGncNaDmijF-nAC8G_vgv9EeNfBrfhrmQHLJuAsCpG2wwS20xDimgJS7yypgTZrqdIF8Cu97AUqiFax7rMCKABuzDzpN2xYBgFJdn0h0FexK5y2ZfyT59M"
          />
        </div>

        <div className="mb-6">
          <p className="font-sans text-body-md text-on-surface-variant text-center max-w-xs mx-auto leading-relaxed">
            Enter your details to create a new driver account for Schneider Park.
          </p>
        </div>

        {error && (
          <div className="mb-5 p-4 rounded-xl bg-error-container text-on-error-container text-body-sm font-medium border border-error/20 flex items-center gap-2">
            <span className="material-symbols-outlined text-lg">error</span>
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6 flex-1 flex flex-col">
          {/* Full Name */}
          <div className="flex flex-col gap-1.5">
            <label className="font-sans text-label-bold text-on-surface font-bold ml-1" htmlFor="fullName">
              Full Name
            </label>
            <div className="relative">
              <span className="absolute left-3.5 top-1/2 -translate-y-1/2 material-symbols-outlined text-outline text-lg">
                person
              </span>
              <input
                id="fullName"
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Jane Doe"
                required
                className="w-full bg-white border border-outline-variant rounded-xl py-3.5 pl-11 pr-4 font-sans text-body-md text-on-surface focus:border-primary focus:ring-2 focus:ring-primary/10 transition-all outline-none"
              />
            </div>
          </div>

          {/* Phone Number */}
          <div className="flex flex-col gap-1.5">
            <label className="font-sans text-label-bold text-on-surface font-bold ml-1" htmlFor="phone">
              Phone Number
            </label>
            <div className="relative">
              <span className="absolute left-3.5 top-1/2 -translate-y-1/2 material-symbols-outlined text-outline text-lg">
                phone
              </span>
              <input
                id="phone"
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+1 (555) 000-0000"
                required
                className="w-full bg-white border border-outline-variant rounded-xl py-3.5 pl-11 pr-4 font-sans text-body-md text-on-surface focus:border-primary focus:ring-2 focus:ring-primary/10 transition-all outline-none"
              />
            </div>
          </div>

          {/* Vehicle Number / License Plate */}
          <div className="flex flex-col gap-1.5">
            <label className="font-sans text-label-bold text-on-surface font-bold ml-1" htmlFor="vehicle">
              Vehicle Number / License Plate
            </label>
            <div className="relative">
              <span className="absolute left-3.5 top-1/2 -translate-y-1/2 material-symbols-outlined text-outline text-lg">
                directions_car
              </span>
              <input
                id="vehicle"
                type="text"
                value={vehicleNumber}
                onChange={(e) => setVehicleNumber(e.target.value)}
                placeholder="ABC-1234"
                required
                className="w-full bg-white border border-outline-variant rounded-xl py-3.5 pl-11 pr-4 font-sans text-body-md text-on-surface focus:border-primary focus:ring-2 focus:ring-primary/10 transition-all outline-none uppercase"
              />
            </div>
          </div>

          {/* Push action to bottom */}
          <div className="pt-8 mt-auto">
            <button
              type="submit"
              disabled={submitting}
              className="w-full bg-primary-container text-on-primary-container hover:bg-primary hover:text-white font-sans text-body-lg font-bold py-4 rounded-xl shadow-md hover:shadow-lg transition-all duration-200 active:scale-[0.98] flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
            >
              {submitting ? (
                <span className="material-symbols-outlined text-lg animate-spin">progress_activity</span>
              ) : (
                <>
                  <span>Create Driver Account</span>
                  <span className="material-symbols-outlined text-lg">arrow_forward</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
