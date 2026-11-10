import React from 'react';
import {
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { palette } from '../../../theme/colors/palette';

const worlds = [
  { name: 'NOVA GALLERY', subtitle: 'Social universe', symbol: '✦', color: '#8B6CFF' },
  { name: 'ORBIT NETWORK', subtitle: 'Messages & connections', symbol: '◉', color: '#42DCCB' },
  { name: 'NEXORA ARCADE', subtitle: 'Games & multiplayer', symbol: '◇', color: '#4D8DFF' },
  { name: 'ORACLE CORE', subtitle: 'Artificial intelligence', symbol: '✧', color: '#C18BFF' },
  { name: 'PERSONAL ORBIT', subtitle: 'Your identity & space', symbol: '◎', color: '#67B8FF' },
  { name: 'SOCIAL STATION', subtitle: 'Groups & communities', symbol: '⌘', color: '#4ED9C2' },
  { name: 'NEXORA EXCHANGE', subtitle: 'Digital marketplace', symbol: '⇄', color: '#A58BFF' },
];

export default function HubScreen() {
  const { width } = useWindowDimensions();
  const columns = width >= 600 ? 3 : 2;
  const horizontalPadding = 20;
  const gap = 12;
  const cardWidth =
    (width - horizontalPadding * 2 - gap * (columns - 1)) / columns;

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar barStyle="light-content" />

      <ScrollView
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.header}>
          <View>
            <Text style={styles.brand}>NEXORA</Text>
            <Text style={styles.tagline}>YOUR UNIVERSE. YOUR CONNECTION.</Text>
          </View>
          <View style={styles.status}>
            <View style={styles.statusDot} />
            <Text style={styles.statusText}>STATION ONLINE</Text>
          </View>
        </View>

        <View style={styles.hero}>
          <View style={[styles.orbit, styles.orbitOuter]} />
          <View style={[styles.orbit, styles.orbitInner]} />
          <View style={styles.planetGlow} />
          <View style={styles.planet}>
            <View style={styles.planetShade} />
          </View>

          <View style={styles.heroText}>
            <Text style={styles.eyebrow}>CENTRAL COMMAND</Text>
            <Text style={styles.heroTitle}>Welcome to{'\n'}your universe.</Text>
            <Text style={styles.heroDescription}>
              Seven dimensions. One connected universe.
            </Text>
          </View>
        </View>

        <View style={styles.sectionHeader}>
          <View>
            <Text style={styles.sectionTitle}>Explore NEXORA</Text>
            <Text style={styles.sectionSubtitle}>YOUR SEVEN WORLDS</Text>
          </View>
          <Text style={styles.worldCount}>07 WORLDS</Text>
        </View>

        <View style={styles.worldGrid}>
          {worlds.map((world) => (
            <View
              key={world.name}
              style={[
                styles.worldCard,
                {
                  width: cardWidth,
                  borderColor: `${world.color}55`,
                },
              ]}
            >
              <Text style={[styles.worldSymbol, { color: world.color }]}>
                {world.symbol}
              </Text>
              <Text style={styles.worldName}>{world.name}</Text>
              <Text style={styles.worldSubtitle}>{world.subtitle}</Text>
            </View>
          ))}
        </View>

        <View style={styles.footer}>
          <Text style={styles.footerText}>NEXORA UNIVERSE</Text>
          <Text style={styles.footerVersion}>FOUNDATION BUILD · 1.0.0</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: palette.background,
  },
  content: {
    paddingHorizontal: 20,
    paddingTop: 12,
    paddingBottom: 36,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: 26,
  },
  brand: {
    color: palette.ice,
    fontSize: 25,
    fontWeight: '900',
    letterSpacing: 5,
  },
  tagline: {
    color: palette.muted,
    fontSize: 8,
    letterSpacing: 1.7,
    marginTop: 5,
  },
  status: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#10233A',
    borderRadius: 20,
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  statusDot: {
    width: 7,
    height: 7,
    borderRadius: 4,
    backgroundColor: palette.turquoise,
    marginRight: 7,
  },
  statusText: {
    color: palette.turquoise,
    fontSize: 8,
    fontWeight: '800',
    letterSpacing: 0.8,
  },
  hero: {
    minHeight: 245,
    borderRadius: 25,
    backgroundColor: '#0B1733',
    borderWidth: 1,
    borderColor: '#263B68',
    overflow: 'hidden',
    justifyContent: 'center',
    padding: 22,
    marginBottom: 30,
  },
  orbit: {
    position: 'absolute',
    borderWidth: 1,
    borderColor: 'rgba(91, 139, 255, 0.25)',
    borderRadius: 200,
  },
  orbitOuter: {
    width: 230,
    height: 230,
    right: -70,
    top: 8,
  },
  orbitInner: {
    width: 175,
    height: 175,
    right: -42,
    top: 35,
    borderColor: 'rgba(139, 108, 255, 0.35)',
  },
  planetGlow: {
    position: 'absolute',
    width: 130,
    height: 130,
    borderRadius: 70,
    right: 10,
    top: 58,
    backgroundColor: 'rgba(77, 141, 255, 0.12)',
  },
  planet: {
    position: 'absolute',
    width: 94,
    height: 94,
    borderRadius: 50,
    right: 28,
    top: 76,
    overflow: 'hidden',
    backgroundColor: '#3266B7',
    borderWidth: 1,
    borderColor: '#80B6FF',
  },
  planetShade: {
    position: 'absolute',
    width: 100,
    height: 100,
    left: 35,
    top: -12,
    borderRadius: 50,
    backgroundColor: '#14264E',
  },
  heroText: {
    maxWidth: '78%',
  },
  eyebrow: {
    color: palette.turquoise,
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 2,
    marginBottom: 12,
  },
  heroTitle: {
    color: palette.white,
    fontSize: 27,
    lineHeight: 34,
    fontWeight: '800',
  },
  heroDescription: {
    color: '#AFC2E4',
    fontSize: 11,
    marginTop: 12,
    lineHeight: 17,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    marginBottom: 15,
  },
  sectionTitle: {
    color: palette.ice,
    fontSize: 19,
    fontWeight: '800',
  },
  sectionSubtitle: {
    color: palette.muted,
    fontSize: 9,
    letterSpacing: 1.5,
    marginTop: 5,
  },
  worldCount: {
    color: palette.turquoise,
    fontSize: 9,
    fontWeight: '800',
    letterSpacing: 1,
    paddingBottom: 3,
  },
  worldGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 12,
  },
  worldCard: {
    minHeight: 125,
    backgroundColor: palette.surface,
    borderRadius: 17,
    borderWidth: 1,
    padding: 14,
    justifyContent: 'center',
  },
  worldSymbol: {
    fontSize: 25,
    fontWeight: '700',
    marginBottom: 11,
  },
  worldName: {
    color: palette.ice,
    fontSize: 10,
    fontWeight: '900',
    letterSpacing: 0.5,
  },
  worldSubtitle: {
    color: palette.muted,
    fontSize: 9,
    marginTop: 6,
  },
  footer: {
    marginTop: 30,
    paddingTop: 16,
    borderTopWidth: 1,
    borderTopColor: palette.border,
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  footerText: {
    color: palette.muted,
    fontSize: 8,
    letterSpacing: 1.5,
    fontWeight: '800',
  },
  footerVersion: {
    color: '#637697',
    fontSize: 8,
    letterSpacing: 0.5,
  },
});
