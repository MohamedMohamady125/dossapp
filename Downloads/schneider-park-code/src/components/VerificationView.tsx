import React, { useRef, useState, useEffect } from 'react';

interface VerificationViewProps {
  onBack: () => void;
  onVerify: (code: string) => Promise<void>;
  onResend: () => Promise<void>;
  destinationText: string;
}

export default function VerificationView({ onBack, onVerify, onResend, destinationText }: VerificationViewProps) {
  const [code, setCode] = useState(['', '', '', '']);
  const [resending, setResending] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const inputRefs = [
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
    useRef<HTMLInputElement>(null),
  ];

  useEffect(() => {
    if (inputRefs[0].current) {
      inputRefs[0].current.focus();
    }
  }, []);

  const handleChange = (index: number, value: string) => {
    setError('');
    const cleanValue = value.replace(/[^0-9]/g, '');

    const newCode = [...code];
    newCode[index] = cleanValue.slice(-1);
    setCode(newCode);

    if (cleanValue.length > 0 && index < 3) {
      setTimeout(() => {
        inputRefs[index + 1].current?.focus();
      }, 20);
    }
  };

  const handleKeyDown = (index: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !code[index] && index > 0) {
      inputRefs[index - 1].current?.focus();
    }
  };

  const handlePaste = (e: React.ClipboardEvent) => {
    e.preventDefault();
    const pastedText = e.clipboardData.getData('text').replace(/[^0-9]/g, '').slice(0, 4);
    if (pastedText) {
      const newCode = ['', '', '', ''];
      for (let i = 0; i < pastedText.length; i++) {
        newCode[i] = pastedText[i];
      }
      setCode(newCode);
      const nextIndex = Math.min(pastedText.length, 3);
      inputRefs[nextIndex].current?.focus();
    }
  };

  const handleVerifySubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    const joined = code.join('');

    if (joined.length < 4) {
      setError('Please enter the complete 4-digit code.');
      return;
    }

    setSubmitting(true);
    try {
      await onVerify(joined);
    } catch (err: any) {
      setError(err.message || 'Invalid verification code.');
    } finally {
      setSubmitting(false);
    }
  };

  const handleResend = async () => {
    setResending(true);
    setMessage('');
    setError('');
    try {
      await onResend();
      setMessage('A new code has been sent successfully.');
    } catch (err: any) {
      setError(err.message || 'Failed to resend code.');
    } finally {
      setResending(false);
    }
  };

  return (
    <div className="w-full max-w-md mx-auto min-h-screen flex flex-col pt-20 pb-12 px-6">
      {/* Top Header */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-surface/90 backdrop-blur-md z-50 flex items-center justify-between border-b border-outline-variant/30 px-6">
        <button
          onClick={onBack}
          aria-label="Go back"
          className="text-primary hover:bg-surface-container-low p-2 rounded-full transition-colors flex items-center justify-center cursor-pointer"
        >
          <span className="material-symbols-outlined">arrow_back</span>
        </button>
        <span className="font-sans text-headline-md font-bold text-primary absolute left-1/2 -translate-x-1/2">
          Schneider Park
        </span>
        <div className="w-10"></div>
      </header>

      {/* Main Container */}
      <div className="flex-1 flex flex-col justify-start">
        {/* Subtle Corporate Logo */}
        <div className="flex justify-center mb-6 mt-4 opacity-30">
          <img
            alt="Schneider Electric Logo"
            className="h-10 object-contain select-none"
            src="https://lh3.googleusercontent.com/aida-public/AB6AXuBOtc1Nibrhm4876c6ngnif6XR6faanXZLCXolRfj7J_e5iCOQAWS1FIg2qbz-IerfKsXU_wRFFSV2_Y6ZvI26HX2w23qvLeqKIAZiMdfsFxMzVyw_uruBB2NH2HQMhFvdxrdbk4q8ACHiDw6VKXBePHn3MwnlIJK2goVU-JGerI_dzcsEndW7JHrwUbHJLoWmMKHAwC1mbc43a2HNbko-tlSzR-szka4EiyI75pHjVz292EoEwoEHki3yvo-tbINiZxwsrOI_hsPk"
          />
        </div>

        <div className="mb-8 text-center">
          <h2 className="font-sans text-3xl font-bold text-on-surface mb-2 tracking-tight">
            Enter Code
          </h2>
          <p className="font-sans text-body-lg text-on-surface-variant max-w-sm mx-auto leading-relaxed">
            A 4-digit code has been sent to <span className="font-bold text-on-surface">{destinationText}</span>.
          </p>
        </div>

        {error && (
          <div className="mb-5 p-4 rounded-xl bg-error-container text-on-error-container text-body-sm font-medium border border-error/20 flex items-center gap-2">
            <span className="material-symbols-outlined text-lg">error</span>
            {error}
          </div>
        )}

        {message && (
          <div className="mb-5 p-4 rounded-xl bg-[#e8f0e3] text-on-tertiary-container text-body-sm font-medium border border-primary/20 flex items-center gap-2">
            <span className="material-symbols-outlined text-lg">check_circle</span>
            {message}
          </div>
        )}

        <form onSubmit={handleVerifySubmit} className="flex-grow flex flex-col">
          {/* OTP inputs container */}
          <div className="flex justify-center gap-4 mb-10" onPaste={handlePaste}>
            {code.map((val, idx) => (
              <input
                key={idx}
                ref={inputRefs[idx]}
                type="text"
                pattern="[0-9]*"
                inputMode="numeric"
                maxLength={1}
                value={val}
                onChange={(e) => handleChange(idx, e.target.value)}
                onKeyDown={(e) => handleKeyDown(idx, e)}
                className="w-16 h-20 text-center font-sans text-3xl font-bold bg-white border border-outline-variant rounded-xl focus:border-primary focus:ring-4 focus:ring-primary/15 focus:outline-none transition-all outline-none"
              />
            ))}
          </div>

          <div className="mt-auto">
            <button
              type="submit"
              disabled={submitting}
              className="w-full bg-primary-container text-on-primary-container hover:bg-primary hover:text-white font-sans text-headline-md py-4 rounded-xl shadow-md hover:shadow-lg transition-all duration-200 active:scale-[0.98] flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
            >
              {submitting ? (
                <span className="material-symbols-outlined text-lg animate-spin">progress_activity</span>
              ) : (
                <>
                  <span>Verify &amp; Proceed</span>
                  <span className="material-symbols-outlined text-lg">arrow_forward</span>
                </>
              )}
            </button>

            <div className="text-center mt-6">
              <p className="font-sans text-body-sm text-on-surface-variant">
                Didn't receive the code?{' '}
                <button
                  type="button"
                  onClick={handleResend}
                  disabled={resending}
                  className="text-primary font-bold hover:underline focus:outline-none cursor-pointer ml-1 disabled:opacity-50"
                >
                  {resending ? 'Sending...' : 'Resend Code'}
                </button>
              </p>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}
