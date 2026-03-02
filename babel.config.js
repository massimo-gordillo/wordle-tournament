module.exports = function (api) {
  api.cache(true);

  return {
    presets: ['babel-preset-expo'],
    plugins: [
      // Expo Router support
      require.resolve('expo-router/babel'),
      // Match TypeScript path alias "@/..."
      [
        'module-resolver',
        {
          alias: {
            '@': './',
          },
        },
      ],
      // Keep this as the last plugin
      'react-native-reanimated/plugin',
    ],
  };
};

