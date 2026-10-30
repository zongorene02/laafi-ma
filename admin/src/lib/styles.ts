// Classes Tailwind partagées (boutons, champs) pour une console homogène.

export const inputClass =
  "mt-1 w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 focus:border-brand-500 focus:ring-2 focus:ring-brand-100 focus:outline-none disabled:bg-gray-100";

export const labelClass = "block text-sm font-medium text-gray-700";

const buttonBase =
  "inline-flex items-center justify-center gap-1.5 rounded-lg px-4 py-2 text-sm font-semibold transition focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50";

export const btnPrimary = `${buttonBase} bg-brand-600 text-white hover:bg-brand-700`;
export const btnSecondary = `${buttonBase} border border-gray-300 bg-white text-gray-800 hover:bg-gray-50`;
export const btnDanger = `${buttonBase} border border-red-200 bg-white text-red-700 hover:bg-red-50`;
export const btnSuccess = `${buttonBase} bg-green-700 text-white hover:bg-green-800`;
export const btnLink =
  "text-sm font-medium text-brand-700 underline-offset-2 hover:underline disabled:cursor-not-allowed disabled:opacity-50";

export const cardClass = "rounded-2xl bg-white p-4 shadow-sm sm:p-6";
