/** @type {import('tailwindcss').Config} */
module.exports = {
  // 告訴 Tailwind 哪些檔案中會用到它的 class
  content: [
    "./pages/**/*.{js,ts,jsx,tsx}",
    "./components/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
};
