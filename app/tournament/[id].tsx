import { useState, useEffect } from 'react';
import { View, Text, StyleSheet, ScrollView, ActivityIndicator, TouchableOpacity } from 'react-native';
import { useLocalSearchParams, router } from 'expo-router';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { ChevronLeft, Trophy } from 'lucide-react-native';
import { getTodayDateEST, getYesterdayDateEST, getDateInEST } from '@/lib/dateUtils';

interface Tournament {
  id: string;
  name: string;
  start_date: string;
  end_date: string;
  status: string;
  join_code: string;
}

interface Score {
  user_id: string;
  total_score: number;
  display_name: string;
  forfeited: boolean;
}

interface Submission {
  user_id: string;
  submission_text: string;
  wordle_score: number;
  display_name: string;
  submission_date: string;
}

export default function TournamentDetailScreen() {
  const { id } = useLocalSearchParams();
  const { user } = useAuth();
  const [tournament, setTournament] = useState<Tournament | null>(null);
  const [scores, setScores] = useState<Score[]>([]);
  const [yesterdaySubmissions, setYesterdaySubmissions] = useState<Submission[]>([]);
  const [loading, setLoading] = useState(true);
  const [resultsReady, setResultsReady] = useState(false);

  useEffect(() => {
    loadTournamentData();

    const channel = supabase
      .channel('tournament-updates')
      .on(
        'postgres_changes',
        {
          event: 'INSERT',
          schema: 'public',
          table: 'daily_submissions',
        },
        () => {
          loadTournamentData();
        }
      )
      .on(
        'postgres_changes',
        {
          event: 'UPDATE',
          schema: 'public',
          table: 'tournament_scores',
          filter: `tournament_id=eq.${id}`,
        },
        () => {
          loadTournamentData();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [id]);


  const loadTournamentData = async () => {
    if (!id) return;

    const { data: tournamentData } = await supabase
      .from('tournaments')
      .select('*')
      .eq('id', id)
      .single();

    if (tournamentData) {
      setTournament(tournamentData);
    }

    const { data: participantsData } = await supabase
      .from('tournament_participants')
      .select('user_id')
      .eq('tournament_id', id);

    const participantIds = participantsData?.map(p => p.user_id) || [];

    const today = getTodayDateEST();
    const { data: todaySubmissions } = await supabase
      .from('daily_submissions')
      .select('user_id')
      .eq('submission_date', today)
      .in('user_id', participantIds);

    const submittedUserIds = todaySubmissions?.map(s => s.user_id) || [];
    const allSubmitted = participantIds.length === submittedUserIds.length;

    const estNow = getDateInEST();
    const isPastCutoff = estNow.getHours() >= 23;

    setResultsReady(allSubmitted || isPastCutoff);

    const { data: allParticipants } = await supabase
      .from('tournament_participants')
      .select('user_id, forfeited')
      .eq('tournament_id', id);

    if (allParticipants) {
      const participantIds = allParticipants.map(p => p.user_id);

      const { data: scoresData } = await supabase
        .from('tournament_scores')
        .select('user_id, total_score')
        .eq('tournament_id', id)
        .in('user_id', participantIds);

      const { data: usersData } = await supabase
        .from('users')
        .select('id, display_name')
        .in('id', participantIds);

      const usersMap = new Map(usersData?.map(u => [u.id, u.display_name]));
      const scoresMap = new Map(scoresData?.map(s => [s.user_id, s.total_score]));
      const forfeitedMap = new Map(allParticipants.map(p => [p.user_id, p.forfeited]));

      const formattedScores = allParticipants
        .map(p => ({
          user_id: p.user_id,
          total_score: scoresMap.get(p.user_id) || 0,
          display_name: usersMap.get(p.user_id) || 'Unknown',
          forfeited: forfeitedMap.get(p.user_id) || false,
        }))
        .sort((a, b) => b.total_score - a.total_score);

      setScores(formattedScores);
    }

    const yesterday = getYesterdayDateEST();
    const { data: submissionsData } = await supabase
      .from('daily_submissions')
      .select('user_id, submission_text, wordle_score, submission_date')
      .eq('submission_date', yesterday)
      .in('user_id', participantIds);

    if (submissionsData) {
      const userIds = submissionsData.map(s => s.user_id);
      const { data: usersData } = await supabase
        .from('users')
        .select('id, display_name')
        .in('id', userIds);

      const usersMap = new Map(usersData?.map(u => [u.id, u.display_name]));

      const formattedSubmissions = submissionsData.map(s => ({
        ...s,
        display_name: usersMap.get(s.user_id) || 'Unknown',
      }));

      setYesterdaySubmissions(formattedSubmissions);
    }

    setLoading(false);
  };

  const renderWordleGrid = (text: string) => {
    const lines = text.split('\n');
    const gridLines = lines.filter(line => /[🟩🟨⬜⬛]/.test(line));

    return gridLines.map((line, index) => (
      <Text key={index} style={styles.wordleRow}>{line}</Text>
    ));
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

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <ChevronLeft size={24} color="#fff" />
        </TouchableOpacity>
        <Text style={styles.title}>{tournament.name}</Text>
      </View>

      <ScrollView style={styles.content}>
        <View style={styles.infoCard}>
          <Text style={styles.infoLabel}>Status</Text>
          <Text style={styles.infoValue}>{tournament.status.toUpperCase()}</Text>
          <Text style={styles.infoLabel}>Duration</Text>
          <Text style={styles.infoValue}>
            {new Date(tournament.start_date).toLocaleDateString()} - {new Date(tournament.end_date).toLocaleDateString()}
          </Text>
          <Text style={styles.infoLabel}>Join Code</Text>
          <Text style={styles.infoValue}>{tournament.join_code}</Text>
        </View>

        {!resultsReady && tournament.status === 'active' && (
          <View style={styles.waitingCard}>
            <Text style={styles.waitingText}>Waiting for today's submissions...</Text>
            <Text style={styles.waitingSubtext}>Results will be available after all players submit or at 11 PM EST</Text>
          </View>
        )}

        <View style={styles.section}>
          <View style={styles.sectionHeader}>
            <Trophy size={20} color="#1a1a1a" />
            <Text style={styles.sectionTitle}>Leaderboard</Text>
          </View>

          {scores.length === 0 ? (
            <Text style={styles.emptyText}>No scores yet</Text>
          ) : (
            scores.map((score, index) => (
              <View key={score.user_id} style={styles.scoreCard}>
                <View style={styles.scoreRank}>
                  <Text style={styles.rankNumber}>#{index + 1}</Text>
                </View>
                <View style={styles.scoreInfo}>
                  <Text style={styles.scoreName}>
                    {score.display_name}
                    {score.forfeited && <Text style={styles.forfeitedText}> (Forfeited)</Text>}
                  </Text>
                </View>
                <Text style={styles.scorePoints}>{score.total_score} pts</Text>
              </View>
            ))
          )}
        </View>

        {yesterdaySubmissions.length > 0 && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Yesterday's Results</Text>
            {yesterdaySubmissions.map((submission) => (
              <View key={submission.user_id} style={styles.submissionCard}>
                <View style={styles.submissionHeader}>
                  <Text style={styles.submissionName}>{submission.display_name}</Text>
                  <Text style={styles.submissionScore}>{submission.wordle_score} pts</Text>
                </View>
                <View style={styles.wordleGrid}>
                  {renderWordleGrid(submission.submission_text)}
                </View>
              </View>
            ))}
          </View>
        )}
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
  },
  infoCard: {
    backgroundColor: '#fff',
    margin: 16,
    padding: 20,
    borderRadius: 12,
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
    marginTop: 8,
  },
  infoValue: {
    fontSize: 16,
    color: '#1a1a1a',
    fontWeight: '500',
  },
  waitingCard: {
    backgroundColor: '#fef3c7',
    marginHorizontal: 16,
    marginBottom: 16,
    padding: 16,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#fbbf24',
  },
  waitingText: {
    fontSize: 16,
    color: '#92400e',
    fontWeight: '600',
    marginBottom: 4,
  },
  waitingSubtext: {
    fontSize: 14,
    color: '#92400e',
  },
  section: {
    padding: 16,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 16,
    gap: 8,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#1a1a1a',
  },
  scoreCard: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    flexDirection: 'row',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  scoreRank: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#10b981',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 12,
  },
  rankNumber: {
    color: '#fff',
    fontSize: 16,
    fontWeight: 'bold',
  },
  scoreInfo: {
    flex: 1,
  },
  scoreName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1a1a1a',
  },
  forfeitedText: {
    color: '#ef4444',
    fontSize: 14,
  },
  scorePoints: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#10b981',
  },
  emptyText: {
    textAlign: 'center',
    color: '#666',
    fontSize: 14,
    paddingVertical: 20,
  },
  submissionCard: {
    backgroundColor: '#fff',
    padding: 16,
    borderRadius: 12,
    marginBottom: 12,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4,
    elevation: 3,
  },
  submissionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  submissionName: {
    fontSize: 16,
    fontWeight: '600',
    color: '#1a1a1a',
  },
  submissionScore: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#10b981',
  },
  wordleGrid: {
    alignItems: 'center',
    paddingVertical: 8,
  },
  wordleRow: {
    fontSize: 20,
    marginBottom: 2,
    letterSpacing: 4,
  },
});
