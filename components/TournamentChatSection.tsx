import { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  ActivityIndicator,
  Platform,
} from 'react-native';
import { Lock, Send } from 'lucide-react-native';

export interface TournamentChatMessage {
  id: string;
  user_id: string;
  message: string;
  message_type: 'chat' | 'result';
  submission_date: string | null;
  created_at: string;
  display_name: string;
}

interface TournamentChatSectionProps {
  messages: TournamentChatMessage[];
  currentUserId: string | undefined;
  todayEst: string;
  resultsReadyForToday: boolean;
  canCompose: boolean;
  sending: boolean;
  onSend: (text: string) => Promise<void>;
}

function resultIsRevealed(
  submissionDate: string | null,
  todayEst: string,
  resultsReadyForToday: boolean,
): boolean {
  if (!submissionDate) return true;
  if (submissionDate < todayEst) return true;
  if (submissionDate === todayEst) return resultsReadyForToday;
  return false;
}

export function TournamentChatSection({
  messages,
  currentUserId,
  todayEst,
  resultsReadyForToday,
  canCompose,
  sending,
  onSend,
}: TournamentChatSectionProps) {
  const [draft, setDraft] = useState('');

  const handleSend = async () => {
    const t = draft.trim();
    if (!t || sending) return;
    setDraft('');
    await onSend(t);
  };

  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle}>Tournament chat</Text>

      <View style={styles.feed}>
        {messages.length === 0 ? (
          <Text style={styles.emptyText}>No messages yet</Text>
        ) : (
          messages.map(msg => {
            if (msg.message_type === 'result') {
              const revealed = resultIsRevealed(
                msg.submission_date,
                todayEst,
                resultsReadyForToday,
              );
              return (
                <View key={msg.id} style={styles.resultRow}>
                  {revealed ? (
                    <View style={styles.resultRevealedBox}>
                      <Text style={styles.resultRevealedMeta}>
                        {msg.display_name}&apos;s Wordle
                      </Text>
                      <Text style={styles.resultRevealedText} selectable>
                        {msg.message}
                      </Text>
                    </View>
                  ) : (
                    <View style={styles.resultLockedBox}>
                      <Lock size={16} color="#6b7280" style={styles.lockIcon} />
                      <Text style={styles.resultLockedText}>
                        {msg.display_name} has submitted their result
                      </Text>
                    </View>
                  )}
                </View>
              );
            }

            const isSelf = msg.user_id === currentUserId;
            return (
              <View
                key={msg.id}
                style={[styles.chatRow, isSelf ? styles.chatRowSelf : styles.chatRowOther]}
              >
                {!isSelf && (
                  <Text style={styles.peerName}>{msg.display_name}</Text>
                )}
                <View style={[styles.bubble, isSelf ? styles.bubbleSelf : styles.bubbleOther]}>
                  <Text style={[styles.bubbleText, isSelf && styles.bubbleTextSelf]}>
                    {msg.message}
                  </Text>
                </View>
              </View>
            );
          })
        )}
      </View>

      {canCompose && (
        <View style={styles.composer}>
          <TextInput
            style={styles.input}
            value={draft}
            onChangeText={setDraft}
            placeholder="Message…"
            placeholderTextColor="#9ca3af"
            multiline
            maxLength={400}
            editable={!sending}
          />
          <TouchableOpacity
            style={[styles.sendBtn, (sending || !draft.trim()) && styles.sendBtnDisabled]}
            onPress={handleSend}
            disabled={sending || !draft.trim()}
            accessibilityRole="button"
            accessibilityLabel="Send message"
          >
            {sending ? (
              <ActivityIndicator size="small" color="#fff" />
            ) : (
              <Send size={20} color="#fff" />
            )}
          </TouchableOpacity>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  section: {
    paddingHorizontal: 16,
    paddingBottom: 24,
  },
  sectionTitle: {
    fontSize: 20,
    fontWeight: '600',
    color: '#1a1a1a',
    marginBottom: 12,
  },
  feed: {
    minHeight: 80,
  },
  emptyText: {
    textAlign: 'center',
    color: '#666',
    fontSize: 14,
    paddingVertical: 16,
  },
  chatRow: {
    marginBottom: 10,
    maxWidth: '85%',
  },
  chatRowSelf: {
    alignSelf: 'flex-end',
    alignItems: 'flex-end',
  },
  chatRowOther: {
    alignSelf: 'flex-start',
    alignItems: 'flex-start',
  },
  peerName: {
    fontSize: 12,
    color: '#6b7280',
    marginBottom: 4,
    marginLeft: 4,
  },
  bubble: {
    borderRadius: 18,
    paddingVertical: 10,
    paddingHorizontal: 14,
    maxWidth: '100%',
  },
  bubbleSelf: {
    backgroundColor: '#10b981',
  },
  bubbleOther: {
    backgroundColor: '#e5e7eb',
  },
  bubbleText: {
    fontSize: 16,
    color: '#1f2937',
  },
  bubbleTextSelf: {
    color: '#fff',
  },
  resultRow: {
    width: '100%',
    alignItems: 'center',
    marginBottom: 12,
  },
  resultRevealedBox: {
    width: '100%',
    backgroundColor: '#f3f4f6',
    borderRadius: 12,
    padding: 12,
    borderWidth: 1,
    borderColor: '#e5e7eb',
  },
  resultRevealedMeta: {
    fontSize: 12,
    fontWeight: '600',
    color: '#6b7280',
    marginBottom: 8,
    textAlign: 'center',
  },
  resultRevealedText: {
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace', default: 'monospace' }),
    fontSize: 13,
    lineHeight: 18,
    color: '#111827',
  },
  resultLockedBox: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#f9fafb',
    borderRadius: 12,
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderWidth: 1,
    borderColor: '#e5e7eb',
    gap: 8,
    width: '100%',
  },
  lockIcon: {
    marginRight: 0,
  },
  resultLockedText: {
    fontSize: 14,
    color: '#4b5563',
    fontStyle: 'italic',
    flex: 1,
    textAlign: 'center',
  },
  composer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    marginTop: 16,
    gap: 8,
    paddingTop: 8,
    borderTopWidth: 1,
    borderTopColor: '#e5e7eb',
  },
  input: {
    flex: 1,
    minHeight: 44,
    maxHeight: 120,
    backgroundColor: '#fff',
    borderRadius: 22,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 16,
    borderWidth: 1,
    borderColor: '#d1d5db',
    color: '#1a1a1a',
  },
  sendBtn: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#10b981',
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendBtnDisabled: {
    opacity: 0.5,
  },
});
