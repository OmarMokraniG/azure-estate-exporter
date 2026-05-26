/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        azure: {
          50: '#e6f1fb',
          100: '#cce3f7',
          200: '#99c7ef',
          300: '#66abe7',
          400: '#338fdf',
          500: '#0078d4',
          600: '#0062ab',
          700: '#004a82',
          800: '#003258',
          900: '#001a2f',
        },
      },
      fontFamily: {
        sans: ['"Segoe UI"', 'system-ui', '-apple-system', 'sans-serif'],
        mono: ['"Cascadia Code"', '"Consolas"', 'ui-monospace', 'monospace'],
      },
    },
  },
  plugins: [],
};
