import React, { useState } from 'react';

interface CreateAccountViewProps {
  onBack: () => void;
  onRegister: (email: string, password: string) => Promise<void>;
  onLogin: (email: string, password: string) => Promise<void>;
  onGoToLogin: () => void;
  isLoginDefault?: boolean;
}

export default function CreateAccountView({
  onBack,
  onRegister,
  onLogin,
  isLoginDefault = false,
}: CreateAccountViewProps) {
  const [isLogin, setIsLogin] = useState(isLoginDefault);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [agree, setAgree] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!email) {
      setError('Please enter your email.');
      return;
    }

    const lowerEmail = email.toLowerCase().trim();
    if (!lowerEmail.endsWith('@schneider-electric.com') && !lowerEmail.endsWith('@se.com')) {
      setError('Please use your Schneider Electric email (@schneider-electric.com or @se.com).');
      return;
    }

    if (!password) {
      setError('Password is required.');
      return;
    }

    if (!isLogin && password !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    if (!isLogin && !agree) {
      setError('You must agree to the Terms of Service & Privacy Policy.');
      return;
    }

    setSubmitting(true);
    try {
      if (isLogin) {
        await onLogin(email, password);
      } else {
        await onRegister(email, password);
      }
    } catch (err: any) {
      setError(err.message || 'Something went wrong. Please try again.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="w-full max-w-md mx-auto min-h-screen flex flex-col pt-20 pb-10 px-6">
      {/* Dynamic Header */}
      <header className="fixed top-0 left-0 right-0 h-16 bg-surface/90 backdrop-blur-md z-50 flex items-center justify-between border-b border-outline-variant/30 px-6">
        <button
          onClick={onBack}
          aria-label="Go back"
          className="text-primary hover:bg-surface-container-low p-2 rounded-full transition-colors flex items-center justify-center cursor-pointer"
        >
          <span className="material-symbols-outlined">arrow_back</span>
        </button>
        <h1 className="font-sans text-headline-md font-bold text-primary absolute left-1/2 -translate-x-1/2">
          {isLogin ? 'Log In' : 'Register'}
        </h1>
        <div className="w-10"></div>
      </header>

      {/* Main Form Content */}
      <div className="flex-1 flex flex-col justify-start">
        <div className="mb-8 mt-4">
          <h2 className="font-sans text-4xl font-bold text-on-surface mb-2 tracking-tight">
            {isLogin ? 'Sign In' : 'Create Account'}
          </h2>
          <p className="font-sans text-body-md text-on-surface-variant leading-relaxed">
            {isLogin
              ? 'Enter your Schneider Electric credentials to access your account.'
              : 'Enter your Schneider Electric email to get started with Schneider Park.'}
          </p>
        </div>

        {error && (
          <div className="mb-6 p-4 rounded-xl bg-error-container text-on-error-container text-body-sm font-medium border border-error/20 flex items-center gap-2">
            <span className="material-symbols-outlined text-lg">error</span>
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="flex-grow flex flex-col">
          <div className="space-y-5">
            {/* Email field */}
            <div className="relative">
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder=" "
                required
                className="peer w-full pt-6 pb-2 px-4 border border-outline-variant rounded-xl bg-white text-on-surface font-sans text-body-md focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/10 transition-all placeholder-shown:placeholder-transparent"
              />
              <label
                htmlFor="email"
                className="absolute left-4 top-4 text-on-surface-variant font-sans text-body-md transition-all duration-200 pointer-events-none origin-top-left peer-focus:top-1.5 peer-focus:text-xs peer-focus:font-semibold peer-focus:text-primary peer-[:not(:placeholder-shown)]:top-1.5 peer-[:not(:placeholder-shown)]:text-xs"
              >
                Schneider Electric Email
              </label>
            </div>

            {/* Password field */}
            <div className="relative">
              <input
                id="password"
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder=" "
                required
                className="peer w-full pt-6 pb-2 pl-4 pr-12 border border-outline-variant rounded-xl bg-white text-on-surface font-sans text-body-md focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/10 transition-all placeholder-shown:placeholder-transparent"
              />
              <label
                htmlFor="password"
                className="absolute left-4 top-4 text-on-surface-variant font-sans text-body-md transition-all duration-200 pointer-events-none origin-top-left peer-focus:top-1.5 peer-focus:text-xs peer-focus:font-semibold peer-focus:text-primary peer-[:not(:placeholder-shown)]:top-1.5 peer-[:not(:placeholder-shown)]:text-xs"
              >
                Password
              </label>
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-on-surface-variant hover:text-primary transition-colors focus:outline-none cursor-pointer p-1"
                aria-label="Toggle password visibility"
              >
                <span className="material-symbols-outlined text-lg">
                  {showPassword ? 'visibility_off' : 'visibility'}
                </span>
              </button>
            </div>

            {/* Confirm Password field (Sign Up only) */}
            {!isLogin && (
              <div className="relative">
                <input
                  id="confirm_password"
                  type={showConfirmPassword ? 'text' : 'password'}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder=" "
                  required
                  className="peer w-full pt-6 pb-2 pl-4 pr-12 border border-outline-variant rounded-xl bg-white text-on-surface font-sans text-body-md focus:outline-none focus:border-primary focus:ring-2 focus:ring-primary/10 transition-all placeholder-shown:placeholder-transparent"
                />
                <label
                  htmlFor="confirm_password"
                  className="absolute left-4 top-4 text-on-surface-variant font-sans text-body-md transition-all duration-200 pointer-events-none origin-top-left peer-focus:top-1.5 peer-focus:text-xs peer-focus:font-semibold peer-focus:text-primary peer-[:not(:placeholder-shown)]:top-1.5 peer-[:not(:placeholder-shown)]:text-xs"
                >
                  Confirm Password
                </label>
                <button
                  type="button"
                  onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  className="absolute right-4 top-1/2 -translate-y-1/2 text-on-surface-variant hover:text-primary transition-colors focus:outline-none cursor-pointer p-1"
                  aria-label="Toggle password visibility"
                >
                  <span className="material-symbols-outlined text-lg">
                    {showConfirmPassword ? 'visibility_off' : 'visibility'}
                  </span>
                </button>
              </div>
            )}
          </div>

          {/* Compliance Area (terms and conditions) */}
          {!isLogin && (
            <div className="flex items-start mt-6 mb-8">
              <div className="flex items-center h-5">
                <input
                  id="terms"
                  type="checkbox"
                  checked={agree}
                  onChange={(e) => setAgree(e.target.checked)}
                  className="w-5 h-5 accent-primary-container border-outline-variant rounded cursor-pointer"
                />
              </div>
              <div className="ml-3 text-body-sm leading-relaxed text-on-surface-variant">
                <label htmlFor="terms" className="cursor-pointer select-none">
                  I agree to the{' '}
                  <a href="#" className="text-primary font-bold hover:underline" onClick={(e) => e.preventDefault()}>
                    Terms of Service
                  </a>{' '}
                  and{' '}
                  <a href="#" className="text-primary font-bold hover:underline" onClick={(e) => e.preventDefault()}>
                    Privacy Policy
                  </a>
                  .
                </label>
              </div>
            </div>
          )}

          {/* Spacer or regular flows */}
          <div className="mt-auto pt-8">
            <button
              type="submit"
              disabled={submitting}
              className="w-full bg-primary-container text-on-primary-container hover:bg-primary hover:text-white font-sans text-body-lg font-bold py-4 rounded-xl shadow-sm hover:shadow-md transition-all duration-200 active:scale-[0.98] flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
            >
              {submitting ? (
                <span className="material-symbols-outlined text-lg animate-spin">progress_activity</span>
              ) : (
                <>
                  <span>{isLogin ? 'Log In' : 'Register'}</span>
                  <span className="material-symbols-outlined text-lg">arrow_forward</span>
                </>
              )}
            </button>

            <p className="mt-5 text-center font-sans text-body-sm text-on-surface-variant">
              {isLogin ? "Don't have an corporate account?" : 'Already have an account?'}{' '}
              <button
                type="button"
                onClick={() => {
                  setIsLogin(!isLogin);
                  setError('');
                }}
                className="text-primary font-bold hover:underline focus:outline-none cursor-pointer ml-1"
              >
                {isLogin ? 'Register now' : 'Log in'}
              </button>
            </p>
          </div>
        </form>
      </div>
    </div>
  );
}
