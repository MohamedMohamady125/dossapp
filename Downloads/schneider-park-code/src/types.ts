export type UserType = 'employee' | 'driver';

export interface UserProfile {
  id?: number;
  name: string;
  email: string;
  phone: string;
  vehicleNumber?: string;
  isDriver: boolean;
}

export type RoleScreen =
  | 'splash'
  | 'register-employee'
  | 'register-driver'
  | 'verify'
  | 'login'
  | 'app-passenger'
  | 'app-driver'
  | 'profile';

export interface CampusLocation {
  id: string;
  name: string;
  description: string;
  icon: string;
}

export interface RideRequest {
  id: string;
  from: string;
  to: string;
  passengerCount: number;
  status: 'pending' | 'accepted' | 'arriving' | 'picked_up' | 'arrived' | 'completed' | 'cancelled';
  passengerName?: string;
  driverName?: string;
  driverPhone?: string;
  vehicleNumber?: string;
  etaMinutes?: number;
}
