const API_BASE = '/api';

let authToken: string | null = null;

export function setToken(token: string | null) {
  authToken = token;
  if (token) {
    localStorage.setItem('schneider_park_token', token);
  } else {
    localStorage.removeItem('schneider_park_token');
  }
}

export function loadToken(): string | null {
  if (!authToken) {
    authToken = localStorage.getItem('schneider_park_token');
  }
  return authToken;
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
  const token = loadToken();
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string> || {}),
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const res = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers,
  });

  const data = await res.json();

  if (!res.ok) {
    const error: any = new Error(data.error || 'Request failed');
    error.status = res.status;
    error.data = data;
    throw error;
  }

  return data as T;
}

// Auth
export interface RegisterPayload {
  name?: string;
  email: string;
  phone?: string;
  password: string;
  vehicleNumber?: string;
  isDriver?: boolean;
}

export interface RegisterResponse {
  message: string;
  userId: number;
  destination: string;
  verificationCode?: string;
}

export interface LoginResponse {
  token: string;
  user: ApiUser;
}

export interface ApiUser {
  id: number;
  name: string;
  email: string;
  phone: string;
  vehicleNumber: string | null;
  isDriver: boolean;
  isAvailable?: boolean;
}

export interface VerifyResponse {
  message: string;
  token: string;
  user: ApiUser;
}

export interface ApiRide {
  id: string;
  from: string;
  to: string;
  passengerCount: number;
  status: string;
  passengerName: string | null;
  passengerPhone: string | null;
  driverName: string | null;
  driverPhone: string | null;
  vehicleNumber: string | null;
  etaMinutes: number;
  createdAt: string;
  updatedAt: string;
}

export interface DriverStats {
  tripsToday: number;
  tripsTotal: number;
  currentOccupancy: number;
  tripsLast30Days: number;
}

export const api = {
  // Auth
  register: (payload: RegisterPayload) =>
    request<RegisterResponse>('/auth/register', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  login: (email: string, password: string) =>
    request<LoginResponse>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    }),

  verify: (userId: number, code: string) =>
    request<VerifyResponse>('/auth/verify', {
      method: 'POST',
      body: JSON.stringify({ userId, code }),
    }),

  resendCode: (userId: number) =>
    request<{ message: string; destination: string; verificationCode?: string }>('/auth/resend-code', {
      method: 'POST',
      body: JSON.stringify({ userId }),
    }),

  getMe: () => request<ApiUser>('/auth/me'),

  // Users
  updateProfile: (name: string, phone?: string) =>
    request<ApiUser>('/users/profile', {
      method: 'PUT',
      body: JSON.stringify({ name, phone }),
    }),

  setAvailability: (isAvailable: boolean) =>
    request<{ isAvailable: boolean }>('/users/availability', {
      method: 'PUT',
      body: JSON.stringify({ isAvailable }),
    }),

  getDriverStats: () => request<DriverStats>('/users/stats'),

  // Rides
  requestRide: (from: string, to: string, passengerCount: number) =>
    request<ApiRide>('/rides', {
      method: 'POST',
      body: JSON.stringify({ from, to, passengerCount }),
    }),

  getActiveRide: () => request<ApiRide | null>('/rides/active'),

  getPendingRides: () => request<ApiRide[]>('/rides/pending'),

  acceptRide: (rideId: string) =>
    request<ApiRide>(`/rides/${rideId}/accept`, { method: 'POST' }),

  updateRideStatus: (rideId: string, status: string) =>
    request<ApiRide>(`/rides/${rideId}/status`, {
      method: 'POST',
      body: JSON.stringify({ status }),
    }),

  cancelRide: (rideId: string) =>
    request<{ message: string }>(`/rides/${rideId}/cancel`, { method: 'POST' }),

  getRideHistory: () => request<ApiRide[]>('/rides/history'),
};
