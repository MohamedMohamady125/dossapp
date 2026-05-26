import React, { useState, useEffect } from 'react';
import SplashView from './components/SplashView';
import CreateAccountView from './components/CreateAccountView';
import DriverRegistrationView from './components/DriverRegistrationView';
import VerificationView from './components/VerificationView';
import EmployeeDashboard from './components/EmployeeDashboard';
import DriverDashboard from './components/DriverDashboard';
import TripProgressView from './components/TripProgressView';
import ProfileView from './components/ProfileView';
import { UserProfile, RoleScreen, RideRequest } from './types';
import { api, setToken, loadToken } from './api';

export default function App() {
  const [screen, setScreen] = useState<RoleScreen>('splash');
  const [currentUser, setCurrentUser] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);

  // Verification helpers
  const [verifyDest, setVerifyDest] = useState('');
  const [pendingUserId, setPendingUserId] = useState<number | null>(null);

  // Active Ride tracker
  const [activeRide, setActiveRide] = useState<RideRequest | null>(null);

  // Driver counter metrics
  const [tripsToday, setTripsToday] = useState(0);

  // On mount: check for existing auth token and restore session
  useEffect(() => {
    const token = loadToken();
    if (token) {
      api.getMe()
        .then((user) => {
          const profile: UserProfile = {
            id: user.id,
            name: user.name,
            email: user.email,
            phone: user.phone,
            vehicleNumber: user.vehicleNumber || undefined,
            isDriver: user.isDriver,
          };
          setCurrentUser(profile);
          setScreen(profile.isDriver ? 'app-driver' : 'app-passenger');

          // Check for active ride
          return api.getActiveRide();
        })
        .then((ride) => {
          if (ride) {
            setActiveRide({
              id: ride.id,
              from: ride.from,
              to: ride.to,
              passengerCount: ride.passengerCount,
              status: ride.status as RideRequest['status'],
              passengerName: ride.passengerName || undefined,
              driverName: ride.driverName || undefined,
              driverPhone: ride.driverPhone || undefined,
              vehicleNumber: ride.vehicleNumber || undefined,
              etaMinutes: ride.etaMinutes,
            });
          }
        })
        .catch(() => {
          setToken(null);
        })
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  // Load driver stats when entering driver dashboard
  useEffect(() => {
    if (screen === 'app-driver' && currentUser?.isDriver) {
      api.getDriverStats()
        .then((stats) => setTripsToday(stats.tripsToday))
        .catch(() => {});
    }
  }, [screen, currentUser]);

  const handleLogout = () => {
    setToken(null);
    setCurrentUser(null);
    setActiveRide(null);
    setScreen('splash');
  };

  const handleSelectRoleFromSplash = (role: 'employee' | 'driver') => {
    if (role === 'employee') {
      setScreen('register-employee');
    } else {
      setScreen('register-driver');
    }
  };

  // Employee registers
  const handleEmployeeRegister = async (email: string, password: string) => {
    const result = await api.register({ email, password, isDriver: false });
    setVerifyDest(result.destination);
    setPendingUserId(result.userId);
    setScreen('verify');
  };

  // Employee logs in
  const handleEmployeeLogin = async (email: string, password: string) => {
    try {
      const result = await api.login(email, password);
      setToken(result.token);
      const profile: UserProfile = {
        id: result.user.id,
        name: result.user.name,
        email: result.user.email,
        phone: result.user.phone,
        vehicleNumber: result.user.vehicleNumber || undefined,
        isDriver: result.user.isDriver,
      };
      setCurrentUser(profile);
      setScreen(profile.isDriver ? 'app-driver' : 'app-passenger');
    } catch (err: any) {
      // If unverified, redirect to verification
      if (err.status === 403 && err.data?.userId) {
        setVerifyDest(err.data.destination);
        setPendingUserId(err.data.userId);
        setScreen('verify');
        return;
      }
      throw err;
    }
  };

  // Driver registers
  const handleDriverRegisterSubmit = async (data: { name: string; phone: string; vehicleNumber: string }) => {
    const email = `${data.name.toLowerCase().replace(/\s+/g, '')}@se.com`;
    const result = await api.register({
      name: data.name,
      email,
      phone: data.phone,
      password: 'driver123',
      vehicleNumber: data.vehicleNumber,
      isDriver: true,
    });
    setVerifyDest(result.destination);
    setPendingUserId(result.userId);
    setScreen('verify');
  };

  // Verify code
  const handleVerifySuccess = async (code: string) => {
    if (!pendingUserId) return;
    const result = await api.verify(pendingUserId, code);
    setToken(result.token);
    const profile: UserProfile = {
      id: result.user.id,
      name: result.user.name,
      email: result.user.email,
      phone: result.user.phone,
      vehicleNumber: result.user.vehicleNumber || undefined,
      isDriver: result.user.isDriver,
    };
    setCurrentUser(profile);
    setPendingUserId(null);
    setScreen(profile.isDriver ? 'app-driver' : 'app-passenger');
  };

  // Resend verification code
  const handleResendCode = async () => {
    if (!pendingUserId) return;
    const result = await api.resendCode(pendingUserId);
    setVerifyDest(result.destination);
  };

  // Employee requests a golf car
  const handleRequestRide = async (passengers: number, from: string, to: string) => {
    const ride = await api.requestRide(from, to, passengers);
    setActiveRide({
      id: ride.id,
      from: ride.from,
      to: ride.to,
      passengerCount: ride.passengerCount,
      status: ride.status as RideRequest['status'],
      passengerName: ride.passengerName || undefined,
      driverName: ride.driverName || undefined,
      vehicleNumber: ride.vehicleNumber || undefined,
      etaMinutes: ride.etaMinutes,
    });
  };

  // Driver accepts request
  const handleAcceptRide = async (ride: RideRequest) => {
    const updated = await api.acceptRide(ride.id);
    setActiveRide({
      id: updated.id,
      from: updated.from,
      to: updated.to,
      passengerCount: updated.passengerCount,
      status: updated.status as RideRequest['status'],
      passengerName: updated.passengerName || undefined,
      driverName: updated.driverName || undefined,
      vehicleNumber: updated.vehicleNumber || undefined,
      etaMinutes: updated.etaMinutes,
    });
  };

  // Ride ended successfully
  const handleCompleteRide = async () => {
    if (activeRide) {
      await api.updateRideStatus(activeRide.id, 'completed').catch(() => {});
    }
    setActiveRide(null);
    if (currentUser?.isDriver) {
      api.getDriverStats()
        .then((stats) => setTripsToday(stats.tripsToday))
        .catch(() => {});
    }
  };

  // Cancel ride
  const handleCancelRide = async () => {
    if (activeRide) {
      await api.cancelRide(activeRide.id).catch(() => {});
    }
    setActiveRide(null);
  };

  const handleUpdateProfileName = async (newName: string) => {
    const updated = await api.updateProfile(newName);
    setCurrentUser((prev) =>
      prev ? { ...prev, name: updated.name } : prev
    );
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-surface">
        <div className="flex flex-col items-center gap-3">
          <span className="material-symbols-outlined text-primary text-5xl animate-spin">progress_activity</span>
          <p className="font-sans text-body-lg text-on-surface-variant">Loading...</p>
        </div>
      </div>
    );
  }

  // Render correct view on active Ride context
  if (activeRide) {
    return (
      <TripProgressView
        ride={activeRide}
        isDriverApp={currentUser?.isDriver || false}
        onCancel={handleCancelRide}
        onComplete={handleCompleteRide}
      />
    );
  }

  // Otherwise, route other UI Screens
  switch (screen) {
    case 'splash':
      return (
        <SplashView
          onSelectRole={handleSelectRoleFromSplash}
          onGoToLogin={() => setScreen('login')}
        />
      );

    case 'register-employee':
      return (
        <CreateAccountView
          onBack={() => setScreen('splash')}
          onRegister={handleEmployeeRegister}
          onLogin={handleEmployeeLogin}
          onGoToLogin={() => setScreen('login')}
        />
      );

    case 'login':
      return (
        <CreateAccountView
          onBack={() => setScreen('splash')}
          onRegister={handleEmployeeRegister}
          onLogin={handleEmployeeLogin}
          onGoToLogin={() => setScreen('login')}
          isLoginDefault={true}
        />
      );

    case 'register-driver':
      return (
        <DriverRegistrationView
          onBack={() => setScreen('splash')}
          onSubmit={handleDriverRegisterSubmit}
        />
      );

    case 'verify':
      return (
        <VerificationView
          onBack={() => setScreen('splash')}
          onVerify={handleVerifySuccess}
          onResend={handleResendCode}
          destinationText={verifyDest}
        />
      );

    case 'app-passenger':
      return (
        <EmployeeDashboard
          onLogout={handleLogout}
          onRequestRide={handleRequestRide}
          onGoToProfile={() => setScreen('profile')}
          userName={currentUser?.name || 'User'}
        />
      );

    case 'app-driver':
      return (
        <DriverDashboard
          onLogout={handleLogout}
          onGoToProfile={() => setScreen('profile')}
          onAcceptRide={handleAcceptRide}
          tripsToday={tripsToday}
        />
      );

    case 'profile':
      if (!currentUser) return <SplashView onSelectRole={handleSelectRoleFromSplash} onGoToLogin={() => setScreen('login')} />;
      return (
        <ProfileView
          profile={currentUser}
          onBack={() => setScreen(currentUser.isDriver ? 'app-driver' : 'app-passenger')}
          onLogout={handleLogout}
          onUpdateName={handleUpdateProfileName}
        />
      );

    default:
      return (
        <SplashView
          onSelectRole={handleSelectRoleFromSplash}
          onGoToLogin={() => setScreen('login')}
        />
      );
  }
}
