import { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, ActivityIndicator, TouchableOpacity, Alert, RefreshControl } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { ChevronLeft, Users, Copy, Play } from 'lucide-react-native';

interface Tournament {
  id: string;
  name: string;
  start_date: string;
  end_date: string;
  status: 'draft' | 'active' | 'closed';
  join_code: string;
  created_by: string;
}

interface Participant {
  id: string;
  user_id: string;
  display_name: string;
}

export default function DraftTournamentScreen() {
  const { id } = useLocalSearchParams();
  const { user } = useAuth();
  const [tournament, setTournament] = useState<Tournament | null>(null);
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [loading, setLoading] = useState(true);
  const [starting, setStarting] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => {
    loadTournamentData();
  }, []);

  const loadTournamentData = async () => {
    if (!id) return;

    const { data: tournamentData } = await supabase
      .from('tournaments')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (tournamentData) {
      setTournament(tournamentData);
    }

    await loadParticipants();
    setLoading(false);
  };

  const loadParticipants = async () => {
    if (!id) return;

    const { data: participantData } = await supabase
      .from('tournament_participants')
      .select('id, user_id')
      .eq('tournament_id', id);

    if (participantData) {
      const userIds = participantData.map(p => p.user_id);
      if (userIds.length === 0) {
        setParticipants([]);
        return;
      }

      const { data: usersData } = await supabase
        .from('users')
        .select('id, display_name')
        .in('id', userIds);

      const usersMap = new Map(usersData?.map(u => [u.id, u.display_name]));

      const formattedParticipants = participantData.map(p => ({
        id: p.id,
        user_id: p.user_id,
        display_name: usersMap.get(p.user_id) || 'Unknown',
      }));

      setParticipants(formattedParticipants);
    }
  };

  const handleCopyCode = () => {
    if (!tournament) return;

    // Web: use the Clipboard API when available
    if (typeof navigator !== 'undefined' && navigator.clipboard) {
      navigator.clipboard.writeText(tournament.join_code);
      return;
    }

    // Native: no-op for now (could be replaced with expo-clipboard)
  };

  const handleStartTournament = async () => {
    if (!tournament || participants.length < 2) return;

    setStarting(true);

    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const originalStartDate = new Date(tournament.start_date);
    const originalEndDate = new Date(tournament.end_date);
    const durationDays = Math.round((originalEndDate.getTime() - originalStartDate.getTime()) / (1000 * 60 * 60 * 24));

    const newEndDate = new Date(today);
    newEndDate.setDate(newEndDate.getDate() + durationDays);

    const { error } = await supabase
      .from('tournaments')
      .update({
        status: 'active',
        start_date: today.toISOString(),
        end_date: newEndDate.toISOString(),
      })
      .eq('id', tournament.id);

    setStarting(false);

    if (!error) {
      router.replace(`/tournament/${tournament.id}`);
    }
  };

  if (loading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color="#10b981" />
      </View>
    );
  }

  if (!tournament) {
    return (
      <View style={styles.loadingContainer}>
        <Text>Tournament not found</Text>
      </View>
    );
  }

  const canStart = participants.length >= 2;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <ChevronLeft size={24} color="#fff" />
        </TouchableOpacity>
        <Text style={styles.title}>{tournament.name}</Text>
      </View>

      <ScrollView
        style={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={async () => {
              setRefreshing(true);
              await loadTournamentData();
              setRefreshing(false);
            }}
          />
        }
      >
        <View style={styles.statusCard}>
          <View style={styles.statusBadge}>
            <Text style={styles.statusText}>DRAFT</Text>
          </View>
          <Text style={styles.statusDescription}>
            Tournament is in draft mode. Share the join code with players and start when ready.
          </Text>
        </View>

        <View style={styles.infoCard}>
          <Text style={styles.infoLabel}>Tournament Duration</Text>
          <Text style={styles.infoValue}>
            {(() => {
              const start = new Date(tournament.start_date);
              const end = new Date(tournament.end_date);
              const days = Math.round((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
              if (days === 3) return '3 days';
              if (days === 7) return '7 days';
              if (days === 14) return '2 weeks';
              if (days === 28) return '4 weeks';
              return `${days} days`;
            })()}
          </Text>
          <Text style={styles.infoSubtext}>
            Starts when you activate the tournament
          </Text>
        </View>

        <View style={styles.joinCodeCard}>
          <View style={styles.joinCodeHeader}>
            <Text style={styles.joinCodeLabel}>Join Code</Text>
            <TouchableOpacity onPress={handleCopyCode} style={styles.copyButton}>
              <Copy size={18} color="#10b981" />
              <Text style={styles.copyButtonText}>Copy</Text>
            </TouchableOpacity>
          </View>
          <Text style={styles.joinCodeValue}>{tournament.join_code}</Text>
          <Text style={styles.joinCodeHint}>Share this code with players to join the tournament</Text>
        </View>

        <View style={styles.participantsSection}>
          <View style={styles.participantsHeader}>
            <Users size={24} color="#1a1a1a" />
            <Text style={styles.participantsTitle}>
              Players ({participants.length}/15)
            </Text>
          </View>

          {participants.length === 0 ? (
            <View style={styles.emptyState}>
              <Text style={styles.emptyText}>No players yet</Text>
              <Text style={styles.emptySubtext}>Waiting for players to join...</Text>
            </View>
          ) : (
            participants.map(participant => (
              <View key={participant.id} style={styles.participantCard}>
                <View style={styles.participantAvatar}>
                  <Text style={styles.participantInitial}>
                    {participant.display_name.charAt(0).toUpperCase()}
                  </Text>
                </View>
                <Text style={styles.participantName}>{participant.display_name}</Text>
              </View>
            ))
          )}
        </View>

        {!canStart && participants.length > 0 && (
          <View style={styles.warningCard}>
            <Text style={styles.warningText}>
              You need at least 2 players to start the tournament
            </Text>
          </View>
        )}

        <TouchableOpacity
          style={[styles.startButton, !canStart && styles.startButtonDisabled]}
          onPress={handleStartTournament}
          disabled={!canStart || starting}
        >
          {starting ? (
            <ActivityIndicator color="#fff" />
          ) : (
            <>
              <Play size={20} color="#fff" />
              <Text style={styles.startButtonText}>Start Tournament</Text>
            </>
          )}
        </TouchableOpacity>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    backgroundColor: '#10b981',
    padding: 24,
    paddingTop: 60,
    flexDirection: 'row',
    alignItems: 'center',
  },
  backButton: {
    marginRight: 12,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    color: '#fff',
    flex: 1,
  },
  content: {
    flex: 1,
    padding: 16,
  },
  statusCard: {
    backgroundColor: '#fff',
    padding: 20,
    borderRadius: 12,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  statusBadge: {
    backgroundColor: '#f59e0b',
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 12,
    alignSelf: 'flex-start',
    marginBottom: 12,
  },
  statusText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  statusDescription: {
    fontSize: 14,
    color: '#666',
    lineHeight: 20,
  },
  infoCard: {
    backgroundColor: '#fff',
    padding: 20,
    borderRadius: 12,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  infoLabel: {
    fontSize: 12,
    color: '#666',
    marginBottom: 4,
  },
  infoValue: {
    fontSize: 16,
    color: '#1a1a1a',
    fontWeight: '500',
  },
  infoSubtext: {
    fontSize: 12,
    color: '#999',
    marginTop: 4,
  },
  joinCodeCard: {
    backgroundColor: '#fff',
    padding: 20,
    borderRadius: 12,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  joinCodeHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  joinCodeLabel: {
    fontSize: 14,
    color: '#666',
    fontWeight: '500',
  },
  copyButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 12,
    paddingVertical: 6,
    backgroundColor: '#f0fdf4',
    borderRadius: 8,
  },
  copyButtonText: {
    fontSize: 14,
    color: '#10b981',
    fontWeight: '500',
  },
  joinCodeValue: {
    fontSize: 36,
    fontWeight: 'bold',
    color: '#10b981',
    letterSpacing: 4,
    textAlign: 'center',
    marginBottom: 8,
  },
  joinCodeHint: {
    fontSize: 12,
    color: '#999',
    textAlign: 'center',
  },
  participantsSection: {
    backgroundColor: '#fff',
    padding: 20,
    borderRadius: 12,
    marginBottom: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  participantsHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 16,
  },
  participantsTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: '#1a1a1a',
  },
  emptyState: {
    alignItems: 'center',
    paddingVertical: 32,
  },
  emptyText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1a1a1a',
    marginBottom: 4,
  },
  emptySubtext: {
    fontSize: 14,
    color: '#666',
  },
  participantCard: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#f3f4f6',
  },
  participantAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#10b981',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  participantInitial: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  participantName: {
    fontSize: 16,
    color: '#1a1a1a',
    fontWeight: '500',
  },
  warningCard: {
    backgroundColor: '#fef3c7',
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
    borderWidth: 1,
    borderColor: '#fbbf24',
  },
  warningText: {
    fontSize: 14,
    color: '#92400e',
    textAlign: 'center',
  },
  startButton: {
    backgroundColor: '#10b981',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    padding: 16,
    borderRadius: 12,
    marginBottom: 24,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  startButtonDisabled: {
    backgroundColor: '#d1d5db',
    opacity: 0.6,
  },
  startButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
});
